"""
Pins (2.0.0-player.18): the albums and artists a user pinned to the app's Home, in the order they
put them there. James: "Pinned albums and artists come next, at the top (pin from an album or artist
page)".

deadwax's OWN, in its database (store.pins) - NEVER Navidrome's stars. A star is per Navidrome user
and means something else there: step 5 of the multi-user plan makes starred albums a person's own
library, James has two other Navidrome users, and Amperfy shows stars as favourites. A pin is a place
on deadwax's Home, and nothing outside deadwax sees it.

What a pin points at - its `ref` - is chosen so the pin follows the thing, not where it happens to be:

  - an ALBUM: `store:<store_album.id>`, the store index's row (src/store.py). That id stays put
    through a re-file (index_move), a release applied, and a disc folder merged into its release's
    (merged_into is followed), so the pin opens the album wherever deadwax moves it. Navidrome's own
    album id is no good for this - Navidrome gives an album a new id when its tags change enough - and
    neither is the path. An album the index doesn't hold yet (pinned before the first scan) is
    `release:<mbid>`, and becomes `store:<id>` on the first read that finds the release indexed.
  - an ARTIST: `mb:<mbid>`, their MusicBrainz id - or, for an artist nobody can say one for (files
    tagged by something else), `name:<their name, folded>`: only how a name was TYPED folds away
    (case, accents, which dash), as artists.py compares names.

This module is the rules, with no I/O: which refs are well formed, what a target's ref is, which
state an album pin is in from the store row it ends at, and the Edit list - the whole ordered list a
PUT takes, applied to what is stored. The routes, which read the store and ask Navidrome, are
src/routes/pins.py.
"""

import re

from src.artists import _fold as fold_name

KINDS = ("album", "artist")

#? How many pins Home holds. Each album pin is looked up in Navidrome as Home asks for them (one
#? getAlbum apiece, side by side), and two columns of fifty cards is already a long Home.
PINS_MAX = 50

#? The longest label, sub-line or name a pin keeps - a long box set's title fits several times over.
LABEL_MAX = 256

#? How many merges are followed from a pinned album's row before giving up: a disc folder merged into
#? its release's is one; a chain this long, or one that loops, is a broken index and the pin is gone.
MERGE_HOPS = 16

#? A MusicBrainz id, as routes/search_musicbrainz.py's MBID_PATTERN takes one (test_pins.py holds the
#? two to one) - written out here so the store, which reads PINS_MAX, imports no route.
MBID_PATTERN = r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

STORE = "store:"
RELEASE = "release:"
MB = "mb:"
NAME = "name:"

_MBID = re.compile(MBID_PATTERN)
_STORE_REF = re.compile(r"^store:([1-9][0-9]{0,17})$")
#? the control characters, which no name typed by a person holds
_CONTROL = re.compile(r"[\x00-\x1f\x7f]")


def is_mbid(value: str | None) -> bool:
    return isinstance(value, str) and bool(_MBID.fullmatch(value))


def store_ref(row_id: int) -> str:
    return f"{STORE}{int(row_id)}"


def release_ref(release_mbid: str) -> str:
    return f"{RELEASE}{release_mbid}"


def artist_ref(mbid: str | None, name: str | None) -> str | None:
    """An artist's ref: their MusicBrainz id when known, else their folded name - None for neither."""
    if is_mbid(mbid):
        return f"{MB}{mbid}"
    folded = fold_name(name or "")
    return f"{NAME}{folded}" if folded and len(folded) <= LABEL_MAX and not _CONTROL.search(folded) else None


def store_id_of(ref: str) -> int | None:
    match = _STORE_REF.fullmatch(ref or "")
    return int(match.group(1)) if match else None


def release_of(ref: str) -> str | None:
    """The release a `release:` ref names - None for any other ref."""
    if ref.startswith(RELEASE) and is_mbid(ref[len(RELEASE):]):
        return ref[len(RELEASE):]
    return None


def mbid_of(ref: str) -> str | None:
    """The MusicBrainz id an artist's `mb:` ref names - None for any other ref."""
    if ref.startswith(MB) and is_mbid(ref[len(MB):]):
        return ref[len(MB):]
    return None


def valid_ref(kind: str, ref: str) -> bool:
    """Whether `ref` is a ref of that kind at all, well formed - what a PUT may name."""
    if not isinstance(ref, str):
        return False
    if kind == "album":
        return store_id_of(ref) is not None or release_of(ref) is not None
    if kind == "artist":
        if mbid_of(ref) is not None:
            return True
        name = ref[len(NAME):] if ref.startswith(NAME) else ""
        return bool(name.strip()) and len(name) <= LABEL_MAX and not _CONTROL.search(name)
    return False


def album_state(row: dict | None, root: str | None) -> str:
    """
    What a pinned album is now, from the store row its pin ends at (merges followed): `present` - a
    live row in this library; `missing` - a scan stopped finding its folder (far more often an
    unmounted share than an album gone; it comes back with the folder), or a row of another library
    root; `gone` - deadwax deleted it, or there is no row to follow at all. A `merged` row here is a
    merge whose target couldn't be followed.
    """
    if row is None:
        return "gone"
    state = row.get("state")
    if state == "present":
        return "present" if not root or row.get("root") == root else "missing"
    if state == "missing":
        return "missing"
    return "gone"


def key(pin: dict) -> tuple[str, str]:
    return pin["kind"], pin["ref"]


def unique(pins: list[dict]) -> list[dict]:
    """Each (kind, ref) once - the first, which is the place the user gave it."""
    seen: set[tuple[str, str]] = set()
    kept = []
    for pin in pins:
        if key(pin) not in seen:
            seen.add(key(pin))
            kept.append(pin)
    return kept


def ordered(stored: list[dict], wanted: list[tuple[str, str]],
            known: list[tuple[str, str]] | None = None) -> list[dict]:
    """
    A PUT's whole ordered list applied to what is stored: the stored pins it names, in its order,
    and nothing else - a stored pin it leaves out is removed (Home's Edit), and a ref it names that
    isn't pinned is passed over: a PUT reorders and removes, it never adds (a pin is made from the
    page of what it pins, which knows its name and picture).

    `known` is the list the page made it from - every pin it had been told of. A stored pin it
    wasn't told of (pinned on another device since the page last asked) is no pin the page meant to
    remove: it keeps its place, and the pins the page did know fill the places they held, in the
    page's order. Without `known`, the list is the whole of it.
    """
    by_key = {key(pin): pin for pin in stored}
    named = unique([by_key[entry] for entry in wanted if entry in by_key])
    if known is None:
        return named
    told = set(known) | {key(pin) for pin in named}
    #? each place a pin the page knew of held is filled by the page's next, in its order; a place
    #? left over is a pin the page removed. There are never more of the page's than places: it names
    #? only stored pins, and each of those it knew of
    queue = iter(named)
    merged = []
    for pin in unique(stored):
        if key(pin) not in told:
            merged.append(pin)
            continue
        following = next(queue, None)
        if following is not None:
            merged.append(following)
    return merged
