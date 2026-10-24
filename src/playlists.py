"""
Playlists (2.0.0-player.58): the pure rules the playlist routes in routes/navidrome.py are made of. No I/O.

The playlists ARE Navidrome's own, made AS THE ASKER (client_for: the signed-in user with logins on, the shared
NAVIDROME_USER with logins off and for the break-glass admin), so Amperfy - which syncs Navidrome's playlists both
ways - shows the same ones. deadwax keeps none of its own: no table, no cache on disk. notes/playlists.md has the
reasoning; what is here:

  - WHOSE. Navidrome lists, to a non-admin, their own playlists and everyone's public ones, and to an admin every
    playlist; its `readonly` is true for anyone but the owner, and for a smart or file-synced playlist even to its
    owner. deadwax decides on `owner`, never on `readonly` alone (an admin sees `readonly: true` on others'
    playlists Navidrome would still let it change): MINE is `owner` equal, case-folded, to the account the call was
    made as; LISTED is mine or public - somebody else's PRIVATE playlist is never listed nor opened, even when the
    account asked as is a Navidrome admin and Navidrome hands it over; EDITABLE is mine and not `readonly`.
  - HIDDEN SONGS. Navidrome's stored counter (getPlaylists' songCount) counts rows whose file is missing; getPlaylist
    lists only the rest. Their difference is how many songs of the playlist aren't in the library just now - for an
    editable playlist only (a smart playlist is re-evaluated as getPlaylist answers, and the counter read beside it
    may be the old one).
  - DUPLICATES. An add of songs some of which are in the playlist already asks first, by default.
  - AN EDIT only removes and reorders: the new list is a rearrangement of a sub-multiset of the old.
"""

import unicodedata
from collections import Counter

#? the longest name and description deadwax writes, and the most songs it edits - held equal to ui/src/lib/playlists.ts
PLAYLIST_NAME_MAX = 200
PLAYLIST_COMMENT_MAX = 1000
PLAYLIST_SONGS_MAX = 2000

GONE = "That playlist isn't on Navidrome any more - deleted in another app, maybe."
NOT_YOURS = "That playlist is {owner}'s - only they can change it."
FROM_FILE = "Navidrome made that playlist from a file in the music folders, so it can't be changed here."
CHANGED = "That playlist changed in another app since you started editing it - nothing was saved."
TOO_LONG = "deadwax edits playlists of up to 2,000 songs - edit this one in Amperfy or Navidrome."
#? (2.0.4) both answered as an Explained (src/auth.py): the sentence for anyone, Navidrome's own words as its `why`
PART_SAVED = "The songs were saved, but Navidrome didn't take the name, description or sharing."
ONLY_REARRANGES = "An edit can only remove and reorder a playlist's songs - add songs with Add to a playlist."
NOT_THE_OWNER = "Navidrome says only the playlist's owner can change it"
BLANK_NAME = "A playlist needs a name."
CONTROL_NAME = "A playlist's name can't hold control characters."
CONTROL_COMMENT = "A description can't hold control characters other than new lines and tabs."
#? (review) the limits in words - the request models' own refusals, which the app's handler (src/api/app.py) sends as
#? a plain `detail` for the playlist routes, so the page shows these rather than "POST ... failed"
SONGS_TOO_MANY = "deadwax adds up to 2,000 songs at a time - add fewer, or use Amperfy or Navidrome."
NAME_TOO_LONG = "A playlist's name can be up to 200 characters."
COMMENT_TOO_LONG = "A description can be up to 1,000 characters."
#? (review) everything was written, and only the read that follows failed: Done again shows it
SAVED_UNREAD = "Saved - but Navidrome didn't answer when deadwax asked for the playlist again."

#? what a description may hold of the control characters: new lines and tabs
COMMENT_CONTROLS = frozenset("\n\r\t")


def _fold(name) -> str:
    return name.casefold() if isinstance(name, str) else ""


def is_mine(playlist: dict, asker: str) -> bool:
    """Whether the playlist is the asker's: its owner, case-folded, is the account the call was made as. A blank
    asker owns nothing (an owner Navidrome left out is nobody's)."""
    folded = _fold(asker).strip()
    return bool(folded) and _fold(playlist.get("owner")).strip() == folded


def is_listed(playlist: dict, asker: str) -> bool:
    """Whether deadwax shows it to the asker at all: theirs, or shared with everyone."""
    return is_mine(playlist, asker) or playlist.get("public") is True


def is_editable(playlist: dict, asker: str) -> bool:
    """Theirs, and not read-only (a smart playlist, or one Navidrome keeps in step with a file). `readonly` missing
    reads as False - Navidrome 0.64.2 always sends it."""
    return is_mine(playlist, asker) and playlist.get("readonly") is not True


def _whole(value) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return 0


def summary(playlist: dict, asker: str) -> dict:
    """deadwax's Playlist: Navidrome's fields it reads, with '' or None for what Navidrome left out, and whose."""
    cover = playlist.get("coverArt")
    return {
        "id": str(playlist.get("id") or ""),
        "name": playlist.get("name") if isinstance(playlist.get("name"), str) else "",
        "comment": playlist.get("comment") if isinstance(playlist.get("comment"), str) else "",
        "songCount": _whole(playlist.get("songCount")),
        "duration": _whole(playlist.get("duration")),
        "created": playlist.get("created") if isinstance(playlist.get("created"), str) else "",
        "changed": playlist.get("changed") if isinstance(playlist.get("changed"), str) else "",
        "owner": playlist.get("owner") if isinstance(playlist.get("owner"), str) else "",
        "public": playlist.get("public") is True,
        "coverArt": cover if isinstance(cover, str) and cover else None,
        "mine": is_mine(playlist, asker),
        "editable": is_editable(playlist, asker),
    }


def songs_of(playlist: dict) -> list[dict]:
    """The songs getPlaylist listed (its `entry`), as Navidrome sent them."""
    entries = playlist.get("entry")
    return [song for song in entries if isinstance(song, dict)] if isinstance(entries, list) else []


def with_songs(playlist: dict, asker: str, hidden: int = 0) -> dict:
    """A PlaylistWithSongs: the summary - its count and length the songs listed - the songs, and how many aren't."""
    songs = songs_of(playlist)
    shown = summary(playlist, asker)
    shown["songCount"] = len(songs)
    shown["duration"] = sum(_whole(song.get("duration")) for song in songs)
    return {"playlist": shown, "songs": songs, "hidden": hidden}


def hidden_count(counter: int, listed: int) -> int:
    """How many of a playlist's songs Navidrome isn't listing just now: its stored counter less the songs listed."""
    return max(0, _whole(counter) - _whole(listed))


def split_duplicates(present: list[str], asked: list[str], mode: str) -> tuple[list[str], int]:
    """What an add writes, and how many of the songs asked for the playlist has already: `skip` only those it
    hasn't, `add` (and `ask`, which the route answers before writing) every one. A song in the playlist twice is
    counted once - `already` is how many of the ASKED songs are there."""
    there = set(present)
    already = sum(1 for song in asked if song in there)
    if mode == "skip":
        return [song for song in asked if song not in there], already
    return list(asked), already


def is_rearrangement(base: list[str], new: list[str]) -> bool:
    """Whether `new` only removes and reorders `base`'s songs: no song it hasn't, nor more copies of one."""
    have = Counter(base)
    return all(count <= have[song] for song, count in Counter(new).items())


def _controls(text: str, allowed: frozenset = frozenset()) -> bool:
    return any(unicodedata.category(char) == "Cc" and char not in allowed for char in text)


def clean_name(text) -> str | None:
    """A name as written: trimmed; None for a blank one or one holding a control character."""
    if not isinstance(text, str):
        return None
    name = text.strip()
    if not name or _controls(name):
        return None
    return name


def clean_comment(text) -> str | None:
    """A description as written: trimmed - '' clears it - new lines and tabs allowed; None for any other control
    character."""
    if not isinstance(text, str):
        return None
    comment = text.strip()
    if _controls(comment, COMMENT_CONTROLS):
        return None
    return comment
