"""
The id bridge (2.0.0-player.17): `GET /deadwax/store/album?release_mbid=...|navidrome_id=...|job_id=...` -
one album as the store index has it, and as Navidrome has it.

An album has three ids, and the app needs to get from any one to the others: Navidrome's album id
(what plays), the store index's row id (`store_album.id`, which stays put through a re-file or a
merge - what pins and step 5's ledger key on) and the MusicBrainz release id (what both sides
share). So this answers, for one release:

  - `present`: the store's live rows of it (index_present) - its folder, edition, year, formats and
    track count; two or more for a set kept one folder per disc. Only folders still there: one that
    has gone becomes a `missing` tombstone, as Find's checks mark one. Tombstones are never listed,
    and a disc folder merged into its release's is not (its row is `merged`; the release's own row
    is the one listed). Since 2.0.0-player.44 each also says what the main page's details pane said
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

(2.1.40) Given `job_id`, the album a download was filed as - the native app's Done row of a MANUAL
search (Search Soulseek), which is filed by its own tags, usually with no release id to be found by. The
job must be the asker's, or the asker has Everyone's downloads (download._job_for's rule - a 404
otherwise, as for no download at all). Its `album_id` (store.set_job_album, the poller's for every
manual filing) leads through index_follow, merges followed, to the live row:
  - none (not filed yet, nothing filed, the row deleted or missing) - the answer with `present: []`;
  - a row matched to a release since (Edit album > Release) - EXACTLY the answer for `release_mbid`
    that release;
  - otherwise `present` is that one row (its folder gone, it is marked `missing` and not listed),
    `other_pressings` none, `release_mbid` and `release_group_mbid` null, `yours` as above, and
    `navidrome_id` Navidrome's album of that name by that artist with NO release id of its own, and the
    row's year and track count wherever both say them (navidrome_album_by_name) - only when exactly one is.

Exactly one of the three is taken (anything else is a 422): a release id as MusicBrainz writes one,
a Navidrome id of at most 256 characters, which is only ever Navidrome's `id` parameter, never
part of a path, or a job id (a whole number from 1). A GET that writes nothing but a tombstone for a
folder that has gone - the same-origin guard has nothing to guard.
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
from src.navidrome_listing import _album_artists, fold_name
from src.organizer import is_within
from src.pins import album_state
#? the library route's own loader of the saved scan, once per process - so the facts below are there
#? after a restart, before anyone has opened the library
from src.routes.library import _ensure_cache_loaded
from src.routes.download import _job_for
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


def _without_release(album: dict) -> bool:
    found = album.get("musicBrainzId")
    return not (isinstance(found, str) and found.strip())


def _year(value) -> str:
    """A year as four digits - Navidrome's `year` is a number, the store row's the date tag's first four
    characters - or '' for none (0, blank, not a year)."""
    if isinstance(value, bool):
        return ""
    if isinstance(value, int):
        return f"{value:04d}" if 0 < value < 10000 else ""
    if isinstance(value, str):
        text = value.strip()[:4]
        return text if len(text) == 4 and text.isdigit() and text != "0000" else ""
    return ""


def _count(value) -> int:
    """A song or track count, 0 for none (missing, not a whole number, not positive)."""
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return max(value, 0)
    if isinstance(value, str) and value.strip().isdigit():
        return int(value.strip())
    return 0


def _is_that_folder(album: dict, name: str, credited: str, year: str, tracks: int) -> bool:
    """Whether a search3 album is the store's id-less folder: see navidrome_album_by_name."""
    if not (isinstance(album, dict) and album.get("id") and _without_release(album)):
        return False
    if not (isinstance(album.get("name"), str) and fold_name(album["name"].strip()) == name):
        return False
    if credited not in _album_artists(album):
        return False
    #? (review) title and artist alone took ANOTHER folder's album - an older id-less copy of the album -
    #? for a download Navidrome hadn't scanned yet. Each is checked only where both sides say it.
    their_year = _year(album.get("year"))
    if year and their_year and their_year != year:
        return False
    songs = _count(album.get("songCount"))
    return not (tracks and songs and songs != tracks)


async def navidrome_album_by_name(client: NavidromeClient, artist: str | None, title: str | None,
                                  year: str | None = None, track_count: int | None = None) -> str | None:
    """
    (2.1.40) Navidrome's album id for an album the store holds with NO release id - a manual search's
    download, filed by its own tags - or None. `year` and `track_count` are the store row's.

    search3 on the album's title, as `client` (the asker's: client_for), and an album believed only when
    it has no `musicBrainzId` of its own (one that has is some matched pressing, never this folder), its
    name folds to the title, the artist is among those Navidrome credits it to - navidrome_listing's own
    fold_name and _album_artists, so this and "Not in Navidrome" can't disagree - and, wherever both sides
    say them, its `year` is the row's and its `songCount` the row's track count. The year and the count are
    what tell this folder from another id-less copy of the album already listed; the count also refuses an
    album Navidrome is still scanning (asked again later) and one it made of two id-less copies at once (playing it
    would play both). With none believed - a common title ("Greatest Hits", "Live") can fill the first
    SEARCH_ALBUMS answers with others' - a second search3 on "<artist> <title>", under the same rules.
    EXACTLY ONE such album gives its id: none, or several, give None, rather than open the wrong one.
    Navidrome unset or down is None; a refused login (SignedOut) is raised, as navidrome_album does.
    """
    name, credited = fold_name((title or "").strip()), fold_name((artist or "").strip())
    if not name or not credited:
        return None
    wanted_year, tracks = _year(year), _count(track_count)
    found: set[str] = set()
    for query in dict.fromkeys(((title or "").strip(), f"{(artist or '').strip()} {(title or '').strip()}")):
        try:
            body = await client.call("search3", {
                "query": query, "albumCount": SEARCH_ALBUMS, "artistCount": 0, "songCount": 0,
            })
        except SignedOut:
            raise
        except NavidromeError as e:
            logger.debug(f"no Navidrome album for {artist} - {title}: {e}")
            return None
        found = {str(album["id"]) for album in (body.get("searchResult3") or {}).get("album") or []
                 if _is_that_folder(album, name, credited, wanted_year, tracks)}
        if found:
            break
    return found.pop() if len(found) == 1 else None


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
    What the main page's details pane said of each folder that the store's row doesn't hold (2.0.0-player.44):
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
    job_id: int | None = Query(None, ge=1),
    user: str = Depends(current_user),
):
    """
    One album, across the three ids: the store's rows of the release, its other pressings, and
    Navidrome's album id for each - see the module's note. Exactly one of `release_mbid`,
    `navidrome_id` and `job_id`.
    """
    if sum(key is not None for key in (release_mbid, navidrome_id, job_id)) != 1:
        raise HTTPException(status_code=422, detail="ask by exactly one of release_mbid, navidrome_id and job_id")

    client = client_for(request)
    if job_id is not None:
        return await _by_job(request, client, job_id, user)
    release = release_mbid or await navidrome_release(client, navidrome_id)
    return await _by_release(request, client, release, navidrome_id, user)


async def _by_release(request: Request, client: NavidromeClient, release: str | None, navidrome_id: str | None,
                      user: str) -> dict:
    """The answer for a release (asked by its id, or read from Navidrome's album `navidrome_id`)."""
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


async def _by_job(request: Request, client: NavidromeClient, job_id: int, user: str) -> dict:
    """
    (2.1.40) The album a download was filed as - a manual search's Done row - see the module's note. The
    job is the asker's or they have Everyone's downloads (a 404 otherwise); the rest degrades to an empty
    answer, never an error.
    """
    job = await _job_for(request, job_id, user)
    answer = {"release_mbid": None, "release_group_mbid": None, "navidrome_id": None,
              "present": [], "other_pressings": []}
    store = getattr(request.app.state, "store", None)
    root = Config.LIBRARY_PATH or ""
    album_id = job.get("album_id")
    if not album_id or not _usable(store) or not root:
        return answer
    try:
        followed = await store.index_follow([album_id])
    except Exception as e:
        logger.warning(f"could not read the store for download {job_id}: {e}")
        followed = None
    row = (followed or {}).get(album_id)
    if album_state(row, root) != "present":
        #? nothing to open: deleted, missing, of another library root, or no row at all
        return answer
    release = (row.get("release_mbid") or "").strip()
    if release:
        #? matched to a release since it was filed (Edit album > Release): the album as that release is
        return await _by_release(request, client, release, None, user)

    present: list[dict] = []
    facts: dict[str, dict] = {}
    try:
        present = await _live(store, root, [row])
    except Exception as e:
        logger.warning(f"could not check the folder download {job_id} was filed in: {e}")
        present = []
    if not present:
        #? its folder has gone since (now marked `missing`): nothing to open
        return answer
    try:
        facts = await _facts(request, store, root, present)
    except Exception as e:
        logger.warning(f"could not read what the scan says of download {job_id}'s album: {e}")
        facts = {}
    answer["present"] = [{**_row(row), **facts.get(row["path"], {})} for row in present]
    answer["navidrome_id"] = await navidrome_album_by_name(client, row.get("artist"), row.get("album"),
                                                           row.get("year"), row.get("track_count"))
    #? (2.0.0-player.52) with logins on: whether it is in the asker's own library
    yours = await library_ledger.yours_paths(store, root, user)
    if yours is not None:
        answer["yours"] = any(entry["path"] in yours for entry in present)
    return answer
