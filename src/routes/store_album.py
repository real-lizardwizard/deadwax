"""
The id bridge (2.0.0-player.17): `GET /deadwax/store/album?release_mbid=...|navidrome_id=...` - one
album as the store index has it, and as Navidrome has it.

An album has three ids, and the app needs to get from any one to the others: Navidrome's album id
(what plays), the store index's row id (`store_album.id`, which stays put through a re-file or a
merge - what pins and step 5's ledger key on) and the MusicBrainz release id (what both sides
share). So this answers, for one release:

  - `present`: the store's live rows of it (index_present) - its folder, edition, year, formats and
    track count; two or more for a set kept one folder per disc. Only folders still there: one that
    has gone becomes a `missing` tombstone, as Find's checks mark one. Tombstones are never listed,
    and a disc folder merged into its release's is not (its row is `merged`; the release's own row
    is the one listed). Since 2.0.0-player.44 each also says what the main page's details pane says
    of the folder - an album page's Properties: `size` and `original_year` from the saved scan (None
    and '' while the scan holds no copy of it), and `first_seen` and `imported` (deadwax filed it)
    from its review row (None and False when it has none) - read without touching the disk.
  - `other_pressings`: the album's OTHER pressings the store holds (index_pressings, by the
    release group the present rows carry) - what the album page's "Also: <edition>" chip opens.
  - `navidrome_id`: Navidrome's album for the release, and for each other pressing - asked of
    Navidrome INTERNALLY (search3 by the release id, then by the album's title, an album believed
    only when its `musicBrainzId` IS the release), never by relaying anything the page sent. Null
    when Navidrome isn't set up, can't be reached, or doesn't have it (yet - it may still be
    scanning): the store's half is answered all the same.

Given `navidrome_id`, the release is Navidrome's own reading of the album's files (getAlbum's
`musicBrainzId`, internally, as the turntable's disc art asks it) - none means nothing in the store
can be said to be that album, and the answer is empty but for the id.

(2.0.0-player.52) With logins on, `yours` says whether the album is in the asker's OWN library (their ledger
holds one of its present folders - library_ledger.yours_paths), and each other pressing says the same - what
the album page's "In your library" or "In the store" with Add to my library reads. Left out with logins off,
for the break-glass admin, and when the ledger can't be read.

Exactly one of the two is taken (anything else is a 422): a release id as MusicBrainz writes one,
or a Navidrome id of at most 256 characters, which is only ever Navidrome's `id` parameter, never
part of a path. A GET that writes nothing but a tombstone for a folder that has gone - the
same-origin guard has nothing to guard.
"""

import asyncio
import time
from collections import OrderedDict
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request

from src.api.navidrome_endpoint import NavidromeClient, NavidromeError, SignedOut, client_for
from src import library_ledger
from src.config import Config
from src.library import cached_album
from src.logger import logger
from src.organizer import is_within
#? the library route's own loader of the saved scan, once per process - so the facts below are there
#? after a restart, before anyone has opened the library
from src.routes.library import _ensure_cache_loaded
from src.routes.navidrome import ID_MAX
from src.routes.search_musicbrainz import MBID_PATTERN
from src.users import current_user

router = APIRouter()

#? How many of the album's other pressings get a Navidrome id looked up: the chips the album page
#? draws, with room to spare. A release group held in a dozen folders is not this page's problem.
OTHER_PRESSINGS_LOOKED_UP = 5

#? How many albums one search3 is asked for: enough to find one pressing among an album's others
#? (Dummy's CD, its vinyl and a remaster are three albums of one title).
SEARCH_ALBUMS = 20

#? Release id -> Navidrome album id, once found: an album page, a Done row and Info all ask about
#? the same few albums, and each lookup is up to two searches of the library. Kept a while and no
#? longer - Navidrome gives an album a new id when its tags change enough - and only what was FOUND:
#? an album Navidrome hasn't scanned yet is asked about afresh next time. A kept id is CHECKED with
#? getAlbum before each use (navidrome_album, 2.0.0-player.21) and looked up afresh when Navidrome no
#? longer has it as that release - an album renamed by an apply moments after it was found, by a
#? Navidrome that ids albums by folder. Home's pins (2.0.0-player.18, src/routes/pins.py) also check
#? each id they open, and forget one gone (forget_navidrome_id).
NAVIDROME_IDS_KEPT = 256
NAVIDROME_ID_SECONDS = 600.0

_navidrome_ids: "OrderedDict[str, tuple[str, float]]" = OrderedDict()


def forget_navidrome_ids() -> None:
    """Every release's Navidrome id forgotten (the tests; a Navidrome URL changing)."""
    _navidrome_ids.clear()


def forget_navidrome_id(release_mbid: str) -> None:
    """One release's Navidrome id forgotten: the id kept for it named an album Navidrome no longer
    has as that release (pins found it so - src/routes/pins.py - after an album moved)."""
    _navidrome_ids.pop(release_mbid, None)


def known_navidrome_id(release_mbid: str) -> str | None:
    """The Navidrome album id found for a release a moment ago, while it is still kept."""
    return _kept(release_mbid)


def remember_navidrome_id(release_mbid: str, album_id: str) -> None:
    """A Navidrome album id seen to BE the release (its own musicBrainzId), kept as a found one is."""
    _keep(release_mbid, album_id)


def _kept(release_mbid: str) -> str | None:
    entry = _navidrome_ids.get(release_mbid)
    if entry is None:
        return None
    album_id, at = entry
    if time.monotonic() - at > NAVIDROME_ID_SECONDS:
        del _navidrome_ids[release_mbid]
        return None
    _navidrome_ids.move_to_end(release_mbid)
    return album_id


def _keep(release_mbid: str, album_id: str) -> None:
    _navidrome_ids[release_mbid] = (album_id, time.monotonic())
    _navidrome_ids.move_to_end(release_mbid)
    while len(_navidrome_ids) > NAVIDROME_IDS_KEPT:
        _navidrome_ids.popitem(last=False)


def _same_release(album: dict, release_mbid: str) -> bool:
    found = album.get("musicBrainzId")
    return isinstance(found, str) and found.strip().lower() == release_mbid.lower()


def is_release(album: dict, release_mbid: str) -> bool:
    """Whether a Navidrome album answer is this release, by its own musicBrainzId."""
    return _same_release(album, release_mbid)


async def navidrome_album(client: NavidromeClient, release_mbid: str | None, title: str | None = None) -> str | None:
    """
    Navidrome's album id for a release, or None.

    Asked INTERNALLY - search3 by the release id first (Navidrome matches MusicBrainz ids in a
    search), then by the album's title where one is known (a Navidrome that doesn't) - and an album
    is believed only when its own `musicBrainzId` is this release: a title alone finds every pressing
    of the album, and the wrong one would open in its place. Nothing of Navidrome's answer goes back
    to the page but the id. Navidrome unset or down is None, never an error: the store's half of the
    answer doesn't need it.
    """
    if not release_mbid:
        return None
    known = _kept(release_mbid)
    if known:
        #? Checked before it is used (2.0.0-player.21): an apply writes the tags, Navidrome scans, and
        #? the album found then can be renamed a moment later - and a Navidrome that ids albums by
        #? folder gives it a new id, while this one would be handed out for the rest of the while,
        #? the album page following an apply never reaching it. One getAlbum, not up to two searches.
        try:
            body = await client.call("getAlbum", {"id": known})
            album = body.get("album")
            if isinstance(album, dict) and _same_release(album, release_mbid):
                return known
        except SignedOut:
            #? (2.0.0-player.52) the asker's login refused: their session has ended - never "not found"
            raise
        except NavidromeError as e:
            if e.unreachable:
                return known  # Navidrome not there: what was found stands, as it always did
        _navidrome_ids.pop(release_mbid, None)
    for query in dict.fromkeys(term for term in (release_mbid, (title or "").strip()) if term):
        try:
            body = await client.call("search3", {
                "query": query, "albumCount": SEARCH_ALBUMS, "artistCount": 0, "songCount": 0,
            })
        except SignedOut:
            raise
        except NavidromeError as e:
            logger.debug(f"no Navidrome album for {release_mbid}: {e}")
            return None
        for album in (body.get("searchResult3") or {}).get("album") or []:
            if isinstance(album, dict) and album.get("id") and _same_release(album, release_mbid):
                _keep(release_mbid, str(album["id"]))
                return str(album["id"])
    return None


async def album_release(client: NavidromeClient, album_id: str) -> str | None:
    """
    The release a Navidrome album is, by Navidrome's reading of its files - None for an album it has
    with no release id. RAISES NavidromeError when Navidrome couldn't be asked, or has no album by
    that id (its status 404): for a caller that must tell "this album has no release id" apart from
    "Navidrome didn't say" (the pins' toggle, src/routes/pins.py).
    """
    body = await client.call("getAlbum", {"id": album_id})
    album = body.get("album")
    release = album.get("musicBrainzId") if isinstance(album, dict) else None
    return release.strip().lower() if isinstance(release, str) and release.strip() else None


async def navidrome_release(client: NavidromeClient, album_id: str) -> str | None:
    """The release a Navidrome album is, by Navidrome's reading of its files - or None."""
    try:
        return await album_release(client, album_id)
    except SignedOut:
        raise
    except NavidromeError as e:
        logger.debug(f"no release for Navidrome album {album_id!r}: {e}")
        return None


def _usable(store) -> bool:
    return store is not None and bool(getattr(store, "available", False))


def _still_there(root: str, paths: list[str]) -> list[bool]:
    library = Path(root)
    return [is_within(library / path, library) and (library / path).is_dir() for path in paths]


async def _live(store, root: str, rows: list[dict]) -> list[dict]:
    """The rows whose folders are still there; one that has gone becomes a `missing` tombstone."""
    there = await asyncio.to_thread(_still_there, root, [row["path"] for row in rows])
    kept = []
    for row, present in zip(rows, there):
        if present:
            kept.append(row)
        else:
            await store.index_gone(root, row["path"], "missing")
    return kept


async def live_rows(store, root: str, rows: list[dict]) -> list[dict]:
    """The rows whose folders are still there (what the bridge lists) - one that has gone is marked
    `missing`, as Find's checks mark one. For pins too (src/routes/pins.py)."""
    return await _live(store, root, rows)


def _row(row: dict) -> dict:
    """A store row as the page reads it: which folder, and what is in it."""
    return {
        "id": row.get("id"),
        "path": row.get("path") or "",
        "release_mbid": row.get("release_mbid") or None,
        "artist": row.get("artist") or "",
        "album": row.get("album") or "",
        "edition": row.get("edition") or "",
        "year": row.get("year") or "",
        "formats": row.get("formats") or [],
        "track_count": row.get("track_count") or 0,
    }


async def _facts(request: Request, store, root: str, rows: list[dict]) -> dict[str, dict]:
    """
    What the main page's details pane says of each folder that the store's row doesn't hold (2.0.0-player.44):
    its size and original year, as the saved scan read them, and when it was first seen and whether deadwax
    filed it, from its review row. Keyed on the path; nothing read from the disk. A store that can't say
    leaves those two out - the page draws only what it is told.
    """
    paths = [row["path"] for row in rows if row.get("path")]
    if not paths:
        return {}
    await _ensure_cache_loaded(request)
    seen = await store.album_seen(paths)
    facts: dict[str, dict] = {}
    for path in paths:
        scan = cached_album(root, path) or {}
        review = seen.get(path) or {}
        facts[path] = {
            "size": scan.get("total_size") if scan else None,
            "original_year": scan.get("original_year") or "",
            "first_seen": review.get("first_seen") or None,
            "imported": review.get("source") == "import",
        }
    return facts


@router.get("/album")
async def store_album(
    request: Request,
    release_mbid: str | None = Query(None, pattern=MBID_PATTERN),
    navidrome_id: str | None = Query(None, min_length=1, max_length=ID_MAX),
    user: str = Depends(current_user),
):
    """
    One album, across the three ids: the store's rows of the release, its other pressings, and
    Navidrome's album id for each - see the module's note. Exactly one of `release_mbid` and
    `navidrome_id`.
    """
    if (release_mbid is None) == (navidrome_id is None):
        raise HTTPException(status_code=422, detail="ask by exactly one of release_mbid and navidrome_id")

    client = client_for(request)
    release = release_mbid or await navidrome_release(client, navidrome_id)
    answer = {"release_mbid": release, "release_group_mbid": None, "navidrome_id": navidrome_id,
              "present": [], "other_pressings": []}
    if not release:
        return answer

    store = getattr(request.app.state, "store", None)
    root = Config.LIBRARY_PATH or ""
    present: list[dict] = []
    others: list[dict] = []
    facts: dict[str, dict] = {}
    if _usable(store) and root:
        try:
            present = await _live(store, root, await store.index_present(root, release))
            group = next((row["release_group_mbid"] for row in present if row.get("release_group_mbid")), None)
            answer["release_group_mbid"] = group
            if group:
                others = await _live(store, root, await store.index_pressings(root, group, release))
        except Exception as e:
            #? a check that fails says nothing: the album page draws no chip, Info no pressing
            logger.warning(f"could not read the store for {release}: {e}")
            present, others = [], []
        try:
            facts = await _facts(request, store, root, present)
        except Exception as e:
            #? the Properties' lines left out, the rows still answered
            logger.warning(f"could not read what the scan says of {release}: {e}")
            facts = {}

    title = next((row["album"] for row in present if row.get("album")), None)
    if navidrome_id is None:
        answer["navidrome_id"] = await navidrome_album(client, release, title)
    answer["present"] = [{**_row(row), **facts.get(row["path"], {})} for row in present]

    looked_up = others[:OTHER_PRESSINGS_LOOKED_UP]
    ids = await asyncio.gather(*(navidrome_album(client, row.get("release_mbid"), row.get("album") or title)
                                 for row in looked_up))
    answer["other_pressings"] = [
        {**_row(row), "navidrome_id": ids[index] if index < len(ids) else None}
        for index, row in enumerate(others)
    ]
    #? (2.0.0-player.52) with logins on: whether each is in the asker's own library
    yours = await library_ledger.yours_paths(store, root, user) if present or others else None
    if yours is not None:
        #? asked only when the store has a folder of the release (other pressings are found from those)
        answer["yours"] = any(row["path"] in yours for row in present)
        for pressing in answer["other_pressings"]:
            pressing["yours"] = pressing["path"] in yours
    return answer
