"""
Permissions (2.0.0-player.61): what an admin gave an ordinary person, by category - kept in the database
(`permissions`, src/store.py) and held in memory, so every request costs a dict lookup.

James (2026-10-21): "maybe a more comprehensive permissions control would be nice. For each user, maybe 4 or
5 or so categories of checkboxes for permissions like, edit metadata, edit users, edit library, etc". Roles
still work as Navidrome's do: an ADMIN (a Navidrome admin - src/auth.py) HAS EVERY PERMISSION. An admin can
give an ordinary person some of an admin's powers by category, with checkboxes in People
(src/routes/people.py). src/users.py's `require(permission)` is the route guard, and `can` the checks
inside a route; notes/logins.md has the inventory, route by route.

  THE CATEGORIES (CATEGORIES): `request` (Get albums - on by default, so an admin can take it away for a
  listen-only account), `edit` (Edit albums), `library` (Look after the library), `downloads` (Everyone's
  downloads), `server` (Settings and the log) - off by default. `people` is not one: it comes with being a
  Navidrome admin, since Navidrome refuses account changes from anyone else (src/users.py).

  ONLY THE DIFFERENCES ARE STORED - a row where an admin changed a category from its default - so a default
  changed later reaches everyone never changed.

  BOUND TO THE ACCOUNT, NOT THE NAME: a row keeps the Navidrome account's id as People's list showed it. A
  GRANT is honoured only for a session whose sign-in read that same id (sessions.navidrome_id - src/auth.py
  _account_id); a RESTRICTION (`request` taken away) by name, always - taking away is never bypassed by an
  id that couldn't be read. A deleted-and-remade account (the same name, another id) inherits no grant.

  WRITTEN DATABASE FIRST, then memory, so a change is in force at the person's next request - no sign-in.
  ONE PROCESS: deadwax runs as one, so memory is the truth once loaded; with another writer this would need
  to read the table per request.

  FAIL CLOSED: a table that can't be read leaves ordinary people with NO permission - not even `request` -
  and is tried again at most every RETRY_SECONDS (a request asks; the lifespan loads it at start-up).
"""

import threading
import time

from src.logger import logger

#? The categories an admin can tick, in the order People shows them (src/users.py PERMISSIONS adds `people`)
CATEGORIES = ("request", "edit", "library", "downloads", "server")

#? An ordinary person's, before an admin changes anything: Get albums only
DEFAULTS = {"request": True, "edit": False, "library": False, "downloads": False, "server": False}

#? How long after a failed read of the table it is read again
RETRY_SECONDS = 60.0

_lock = threading.Lock()
#? the table as last read - user -> {category: (granted, navidrome_id)} - and for which database
_state: dict = {"path": None, "rows": {}, "loaded": False, "failed_at": None}


def forget_all() -> None:
    """Drop what is held (tests; a restart) - the next ask reads the table again."""
    with _lock:
        _state.update(path=None, rows={}, loaded=False, failed_at=None)


def _path(store) -> str | None:
    return getattr(store, "path", None)


def load(store) -> bool:
    """Read the table into memory - True when it could be read. A failure is logged and leaves nobody but
    an admin any permission until a read works (fail closed)."""
    path = _path(store)
    try:
        if store is None or not getattr(store, "available", False):
            raise RuntimeError("deadwax's database isn't open")
        rows = store.permission_rows()
    except Exception as e:
        with _lock:
            _state.update(path=path, rows={}, loaded=False, failed_at=time.monotonic())
        logger.error(f"could not read the permissions admins gave people ({type(e).__name__}: {e}) - until it can, "
                     f"nobody but an admin can do more than play and browse, not even get albums", extra={"frontend": True})
        return False
    table: dict[str, dict[str, tuple[bool, str]]] = {}
    for row in rows:
        if row["permission"] in CATEGORIES:
            table.setdefault(row["user"], {})[row["permission"]] = (bool(row["granted"]), str(row["navidrome_id"]))
    with _lock:
        _state.update(path=path, rows=table, loaded=True, failed_at=None)
    return True


def _ensure(store) -> bool:
    """Whether the table is held for this database - read now if it isn't, unless a read failed in the last
    RETRY_SECONDS."""
    path = _path(store)
    with _lock:
        if _state["loaded"] and _state["path"] == path:
            return True
        failed = _state["failed_at"]
        if _state["path"] == path and failed is not None and time.monotonic() - failed < RETRY_SECONDS:
            return False
    return load(store)


def _rows(user: str) -> dict[str, tuple[bool, str]]:
    with _lock:
        return dict(_state["rows"].get(user, {}))


def ordinary(store, user: str, navidrome_id: str | None) -> frozenset[str]:
    """
    What an ORDINARY person may do (never an admin's, never `people`): the defaults, with what an admin
    changed for them - a grant only when the session read the account id it was given to, a restriction
    always. Nothing at all when the table can't be read.
    """
    if not _ensure(store):
        return frozenset()
    rows = _rows(user)
    found = set()
    for category in CATEGORIES:
        row = rows.get(category)
        if row is None:
            on = DEFAULTS[category]
        elif not row[0]:
            on = False
        else:
            on = DEFAULTS[category] or (navidrome_id is not None and row[1] == navidrome_id)
        if on:
            found.add(category)
    return frozenset(found)


def ticked(store, user: str) -> dict[str, bool] | None:
    """What People shows ticked for `user`: the defaults with every row of theirs, whatever account id it was
    given to - None when the table can't be read."""
    if not _ensure(store):
        return None
    rows = _rows(user)
    return {category: rows[category][0] if category in rows else DEFAULTS[category] for category in CATEGORIES}


def has_grants(store, user: str) -> bool:
    """Whether an admin gave `user` anything beyond the defaults - what makes a sign-in read their account's
    id. SYNCHRONOUS; raises when the table can't be read (the sign-in then reads no id: nothing honoured)."""
    if not _ensure(store):
        raise RuntimeError("the permissions table can't be read")
    return any(granted for granted, _id in _rows(user).values())


def unverified(store, user: str, navidrome_id: str | None) -> bool:
    """Whether `user` has a grant this session doesn't honour - its account id unread, or another: what /me's
    `permissions_unverified` says."""
    if not _ensure(store):
        return False
    return any(granted and (navidrome_id is None or bound != navidrome_id) for granted, bound in _rows(user).values())


def _set_memory(user: str, rows: dict[str, tuple[bool, str]]) -> None:
    with _lock:
        if rows:
            _state["rows"][user] = rows
        else:
            _state["rows"].pop(user, None)


def set_for(store, user: str, navidrome_id: str, wanted: dict[str, bool], by: str) -> tuple[list[str], list[str]]:
    """
    An admin's Save in People: `user`'s rows rewritten to what `wanted` differs from the defaults, bound to
    `navidrome_id` (the account as Navidrome answered just now), `by` named - database first, then memory.
    (What it gave, what it took away), against what was ticked before. SYNCHRONOUS; raises on a database
    error, with memory untouched.
    """
    before = ticked(store, user)
    if before is None:
        raise RuntimeError("the permissions table can't be read")
    rows = {category: (bool(wanted[category]), navidrome_id) for category in CATEGORIES
            if bool(wanted[category]) != DEFAULTS[category]}
    store.set_permissions(user, [(category, granted, navidrome_id) for category, (granted, _id) in rows.items()], by)
    _set_memory(user, rows)
    gave = [category for category in CATEGORIES if wanted[category] and not before[category]]
    took = [category for category in CATEGORIES if not wanted[category] and before[category]]
    return gave, took


def drop_other_accounts(store, user: str, navidrome_id: str) -> int:
    """
    `user`'s GRANT rows given to another Navidrome account than `navidrome_id` - one removed and made again
    under the same name - dropped, database first: how many. A restriction stays (it is by name). SYNCHRONOUS;
    raises on a database error.
    """
    if not _ensure(store):
        raise RuntimeError("the permissions table can't be read")
    rows = _rows(user)
    stale = [category for category, (granted, bound) in rows.items() if granted and bound != navidrome_id]
    if not stale:
        return 0
    store.drop_permissions(user, stale)
    _set_memory(user, {category: row for category, row in rows.items() if category not in stale})
    return len(stale)


def forget(user: str) -> None:
    """`user`'s rows gone from memory - after src/store.py forget_person took them out of the database."""
    _set_memory(user, {})
