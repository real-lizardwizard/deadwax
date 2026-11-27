"""
The Library's album list as it was last read from Navidrome, kept for a moment (2.1.49).

`/deadwax/navidrome/album_index` (src/routes/navidrome.py) reads every album of a scope from Navidrome, a page of
500 at a time, to answer one request - and its ETag saved only the download, never the asking. This keeps the
answer it made, encoded, per asker and scope, for INDEX_KEEP_S: a second device, a page opened again, the iPhone
app beside the web one are answered from it without Navidrome being asked at all.

It is a clock, and so it is short, and everything deadwax itself does that changes the list drops what is kept:

  - a star or an unstar made through deadwax (Add and Remove on an album page, and the worker that stars a
    download for whoever asked for it - src/stars.py, src/routes/my_library.py): `forget()`;
  - a play counted through deadwax (2.1.53 - the scrobble route's `submission=true`): the list carries each
    album's `played` and `playCount`, which the Library's Recently played and Most played sort by -
    `forget(user)`, that listener's lists alone;
  - Navidrome seen to have scanned (src/navidrome_listing.py) and a Rescan: `forget()`;
  - the library itself changed by deadwax - a download filed, a retag, a delete, a move
    (library.note_library_changed): `unsettle()`. Navidrome learns of that only when it next scans, some seconds
    or minutes later, which nothing here is told of - so for INDEX_SETTLE_S after it nothing is kept or answered
    from, and every ask reads Navidrome afresh, exactly as before 2.1.49. A new album is never late for this.

What it can be late for is a change made somewhere else - a star in another Subsonic app, a play counted from
one - by INDEX_KEEP_S at most.

Keys are the route's: who asks, the Navidrome account that answers for them, and the scope - one person's list is
never another's. Pure but for the clock; `now` is passed in by the tests.
"""

import time

#? How long a list read from Navidrome answers the asks that follow it. The app's own pages already ask at most
#? once a minute each (ui/src/app/albumIndex.ts INDEX_FRESH_MS), so this is for the asks BETWEEN pages and
#? devices; half of that minute, so a list is never two of them old.
INDEX_KEEP_S = 30

#? How long after deadwax changed the library nothing is kept: long enough for Navidrome's watcher to notice a
#? new folder and scan it (seconds to a minute or two on a large library).
INDEX_SETTLE_S = 180

#? key -> (when it was read, time.monotonic(); its ETag; its body gzipped) - src/api/json_etag.py pack()
_kept: dict[tuple, tuple[float, str, bytes]] = {}
_unsettled_until = 0.0
#? moved by every forget and unsettle: a list whose reading one of them cut across is not kept - it may be from
#? before what happened. One for everybody, and (2.1.53) one a user: a forget of one person's lists - a play is
#? counted every few minutes - cuts across only that person's readings, never everybody else's
_epoch = 0
_user_epochs: dict[str, int] = {}


def epoch(user: str = "") -> tuple[int, int]:
    """Read before a list is asked of Navidrome for `user` (a key's first part), and handed to keep() with it."""
    return _epoch, _user_epochs.get(user, 0)


def kept(key: tuple, now: float | None = None) -> tuple[str, bytes] | None:
    """The list kept for `key` - its ETag and gzipped body - or None: never read, too old, or unsettled."""
    now = time.monotonic() if now is None else now
    if now < _unsettled_until:
        return None
    held = _kept.get(key)
    if held is None:
        return None
    if now - held[0] >= INDEX_KEEP_S:
        _kept.pop(key, None)
        return None
    return held[1], held[2]


def keep(key: tuple, etag: str, packed: bytes, began: tuple[int, int], now: float | None = None) -> None:
    """Keep a list just read - unless a forget of everybody's or of this key's user, or an unsettle, happened
    since `began` (epoch(user) as the reading started), or the library is unsettled."""
    now = time.monotonic() if now is None else now
    if began != epoch(key[0]) or now < _unsettled_until:
        return
    #? copied first (list() of a dict's items is atomic): a writer's thread may be dropping everything
    for old in [k for k, (read, _, _) in list(_kept.items()) if now - read >= INDEX_KEEP_S]:
        _kept.pop(old, None)
    _kept[key] = (now, etag, packed)


def forget(user: str | None = None) -> None:
    """Every kept list dropped - or only `user`'s (the first part of a key)."""
    global _epoch
    if user is None:
        _epoch += 1
        _user_epochs.clear()
        _kept.clear()
        return
    _user_epochs[user] = _user_epochs.get(user, 0) + 1
    for key in [key for key in list(_kept) if key[0] == user]:
        _kept.pop(key, None)


def unsettle(now: float | None = None) -> None:
    """deadwax changed the library: nothing kept, and nothing kept again until Navidrome has had time to scan."""
    global _unsettled_until
    now = time.monotonic() if now is None else now
    _unsettled_until = max(_unsettled_until, now + INDEX_SETTLE_S)
    forget()


def reset() -> None:
    """As at a start (the tests)."""
    global _unsettled_until
    _unsettled_until = 0.0
    forget()
