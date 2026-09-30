"""
The store index kept in step, and the "already have it" checks that read it (step 2 of the
multi-user plan, 2.0.0-player.7).

**Why.** Find on a pressing you already hold searched Soulseek for it all the same, and Download
fetched it a second time - a whole album's worth of somebody's upload, which filing then either
filed nothing of (organizer.find_duplicate, in the folder it files into) or filed as a second copy
beside the first (in any other folder). And two clicks, two
tabs, or a retry racing a new download could each reach slskd for the same release. So Find asks
first, /enqueue and the retries refuse, and one lock per release covers the check, slskd's enqueue
and the job it records.

**The index** is store_album (src/store.py): every album folder in the library, with an id that
survives a rename, because step 5's per-user ledger keys on it. It is fed by every real scan
(reconcile_scan, from routes/library.py's _persist_cache) and by every writer that moves or makes
an album, right after it does:

  filing (poller._organize_if_enabled)      index_folder on the album folder
  apply release (routes/library._retag_apply)  index_folder before any rename pause, then
                                             reindex_merged / reindex_moved / index_folder
  artist refile                              reindex_moved per album
  delete                                     mark_deleted
  tag edits                                  index_folder in place

Art, CD art and lyrics change nothing it holds. A snapshot never touches it: a snapshot is the
last scan, not the disk.

**Nothing counts as held on the index's word alone.** Each folder is looked at before it counts:
it must still be there, its first audio file must be tagged with this release
(organizer.read_album_mbid), and each file's title and (disc, track) are read as filing reads them
- what is held is the release's distinct tracks, not its files. The index says where to look; the
disk says what is there.

**Everything degrades to "not held".** A broken index, an unreadable folder, a database that
wouldn't open - each costs the check, never the download. The worst a failure here can do is let a
second copy through, which filing's own duplicate rules then catch.
"""

import asyncio
import os
import unicodedata
from collections import Counter
from contextlib import asynccontextmanager
from pathlib import Path

from src.config import Config
from src.library import SCAN_FORMAT, edition_from_dirname, read_album_dir
from src.logger import logger
from src.matching import AUDIO_EXTENSIONS, file_extension, normalize
from src.organizer import existing_tracks, planned_key, read_album_mbid, resolve_album_dir


def _usable(store) -> bool:
    return store is not None and bool(getattr(store, "available", False))


def _inside(relative: Path) -> str | None:
    """A relative path as the index spells it - or None for one that climbs out of the library."""
    return None if ".." in relative.parts else str(relative)


def library_relative(root: str, path) -> str | None:
    """
    `path` relative to the library, the way read_album_dir computes an album's `path` - or None
    when it isn't inside it.

    The writers hand over `Path(root) / ...` (filing's album_dir, an apply's source and target,
    a tag edit's folder, the saved scan's keys), and the routes hand over paths already
    relative to the library (delete, refile). So the path is taken as given first - which is
    what makes a RELATIVE LIBRARY_PATH work: `music/Portishead/Dummy` against `music` - and only
    when it isn't under root, and isn't absolute, as already relative to the library (joining
    root on first made `music/music/...` and indexed nothing). An absolute path against a
    relative root is compared with the root made absolute. Nothing that climbs out (`..`) is
    ever inside. (A known limit, documented: with a relative root, a library path whose artist
    folder has the root's own name - `music/...` against `music` - is read as root-joined.)
    """
    if not root or not path:
        return None
    candidate, base = Path(path), Path(root)
    try:
        return _inside(candidate.relative_to(base))
    except ValueError:
        pass
    if candidate.is_absolute():
        if base.is_absolute():
            return None
        try:
            return _inside(candidate.relative_to(base.absolute()))
        except ValueError:
            return None
    #? already relative to the library
    return _inside(candidate)


def _fold(name: str) -> str:
    """A name as a case- and Unicode-insensitive disk compares it (APFS, exFAT, CIFS)."""
    return unicodedata.normalize("NFC", name).casefold()


def _as_on_disk(root: str, relative: str) -> str:
    """
    `relative` spelled as the disk LISTS it. On a case-insensitive filesystem deadwax's own
    `Portishead/...` opens the folder that is really `portishead/...`, and recorded as written
    it is a path no scan ever reports: two live rows for one folder, for good. Each part is
    taken exactly where the listing has it, else the one entry equal to it ignoring case and
    Unicode form; anything unclear leaves the path as it came.
    """
    current = Path(root)
    parts = []
    for part in Path(relative).parts:
        try:
            names = os.listdir(current)
        except OSError:
            return relative
        if part not in names:
            matches = [name for name in names if _fold(name) == _fold(part)]
            if len(matches) != 1:
                return relative
            part = matches[0]
        parts.append(part)
        current = current / part
    return str(Path(*parts)) if parts else relative


class _Listings:
    """Folder listings, each read once - for asking about several paths in one go."""

    def __init__(self):
        self._names: dict[Path, set[str] | None] = {}

    def names(self, folder: Path) -> set[str] | None:
        if folder not in self._names:
            try:
                self._names[folder] = set(os.listdir(folder))
            except OSError:
                self._names[folder] = None
        return self._names[folder]


def _spelled_exactly(root: str, relative: str, listings: _Listings | None = None) -> bool:
    """
    Whether every part of `relative` is in its parent's listing exactly as spelled. On a
    case-insensitive disk `Portishead/Dummy` opens `portishead/Dummy`, so opening it proves
    nothing: a folder known under two spellings would otherwise keep two live rows for ever.
    """
    listings = listings or _Listings()
    current = Path(root)
    for part in Path(relative).parts:
        names = listings.names(current)
        if names is None or part not in names:
            return False
        current = current / part
    return True


# ---------------------------------------------------------------- keeping it in step

def _read_folder(root: str, relative: str) -> dict | None:
    directory = Path(root) / _as_on_disk(root, relative)
    return read_album_dir(directory, Path(root)) if directory.is_dir() else None


async def index_folder(store, root: str, folder) -> int | None:
    """
    Read one album folder and record it - or, if it no longer holds audio, mark its row
    `missing`. Returns the row id. `folder` is absolute or relative to the library, and is
    recorded as the disk spells it (_as_on_disk). Never raises.
    """
    if not _usable(store) or not root or not folder:
        return None

    relative = library_relative(root, folder)
    if relative is None:
        #? filed somewhere outside the library - LIBRARY_PATH moved under us; nothing to record
        return None

    try:
        album = await asyncio.to_thread(_read_folder, root, relative)
        if album is None:
            await store.index_gone(root, relative, "missing")
            return None
        return await store.index_upsert(root, album)
    except Exception as e:
        logger.warning(f"could not index {relative}: {e}")
        return None


def _moved_to(root: str, new: str) -> tuple[str, str | None]:
    """Where a moved album is now, as the disk spells it, and the release its files say."""
    spelled = _as_on_disk(root, new)
    return spelled, read_album_mbid(Path(root) / spelled)


async def reindex_moved(store, root: str, old_path, new_path) -> int | None:
    """An album folder moved within the library: its row follows (same id), then is re-read."""
    if not _usable(store) or not root:
        return None
    old, new = library_relative(root, old_path), library_relative(root, new_path)
    if old and new:
        try:
            new, release_mbid = await asyncio.to_thread(_moved_to, root, new)
        except Exception:
            release_mbid = None
        await store.index_move(root, old, new, release_mbid)
    return await index_folder(store, root, new or new_path)


async def reindex_merged(store, root: str, source_path, target_path) -> int | None:
    """A disc folder merged into its release's folder: its row becomes `merged`, the target re-read."""
    if not _usable(store) or not root:
        return None
    source, target = library_relative(root, source_path), library_relative(root, target_path)
    if source and target:
        try:
            target = await asyncio.to_thread(_as_on_disk, root, target)
        except Exception:
            pass
        await store.index_merge(root, source, target)
    return await index_folder(store, root, target or target_path)


async def mark_deleted(store, root: str, path) -> None:
    """deadwax deleted this album: its row is kept, as a `deleted` tombstone."""
    relative = library_relative(root, path)
    if _usable(store) and relative:
        await store.index_gone(root, relative, "deleted")


#? Album folders the poller is filing right now (folded relative path -> how many filings), from
#? the moment its plan is made until the folder is indexed. A scan landing mid-copy finds such a
#? folder with no live row, and would pair it, by release, with an unmounted share's tombstone -
#? handing a fresh download the share's id (step 2 review).
_FILING_NOW: dict[str, int] = {}


def filing_started(root: str, album_dir) -> str | None:
    """Mark a folder as being filed. Returns the key to hand filing_finished, or None."""
    relative = library_relative(root, album_dir) if album_dir else None
    if not relative:
        return None
    key = _fold(relative)
    _FILING_NOW[key] = _FILING_NOW.get(key, 0) + 1
    return key


def filing_finished(key: str | None) -> None:
    if key is None or key not in _FILING_NOW:
        return
    _FILING_NOW[key] -= 1
    if _FILING_NOW[key] <= 0:
        del _FILING_NOW[key]


def being_filed(path: str) -> bool:
    return _fold(path) in _FILING_NOW


def _holds_audio(folder: Path) -> bool:
    """Whether audio sits directly in this folder - what makes a folder an album to the scan."""
    try:
        return any(entry.is_file() and file_extension(entry.name) in AUDIO_EXTENSIONS for entry in folder.iterdir())
    except OSError:
        return False


def _still_there(root: str, listings: _Listings):
    def still_there(path: str) -> bool:
        return _spelled_exactly(root, path, listings) and _holds_audio(Path(root) / path)
    return still_there


async def reconcile_scan(store, root: str, albums: list[dict], since: float | None = None) -> None:
    """
    After a real scan: the index in line with it (store.index_reconcile), from when it began.

    A scan can be seconds old when it lands, so the disk is asked again about exactly the
    folders where it and the index disagree - a row it didn't find, a folder it found that
    nothing indexes - before either is written: deadwax may have filed, renamed or deleted it
    meanwhile. The disk is asked for the folder as SPELLED (_spelled_exactly), since on a
    case-insensitive one any spelling opens. After an ordinary scan that is no folder at all. A
    folder the poller is filing right now (being_filed) is never paired with a tombstone.

    The scan's `edition` is DECORATED - an unlabelled folder beside another edition of the same
    album reads "Standard" (library._mark_multi_edition). The index records the folder's own
    edition instead, as index_folder does, so the two writers can't take turns rewriting a row.
    """
    if not _usable(store) or not root:
        return
    try:
        folders = [
            {**album, "edition": edition_from_dirname(Path(album["path"]).name)}
            if album.get("edition") == "Standard" and album.get("path") else album
            for album in albums or []
        ]
        await store.index_reconcile(root, folders, still_there=_still_there(root, _Listings()),
                                    since=since, not_pairable=being_filed)
    except Exception as e:
        #? the scan it follows has already answered; an index that fell behind is caught up next time
        logger.error(f"could not bring the store index up to date: {e}")


async def seed_from_saved_scan(store, root: str) -> int:
    """
    Fill an EMPTY index from the saved scan, at start-up - so an install upgrading to this knows
    its library before anyone has opened the library tab. Never walks the disk: the saved scan
    is one database read, and a start-up that statted every folder on a spun-down array would be
    the thing the saved scan exists to avoid. Entries are keyed on paths built on the root
    (absolute or not, as LIBRARY_PATH is), recorded relative. Returns how many albums were
    recorded. Never raises.
    """
    if not _usable(store) or not root:
        return 0
    try:
        if await store.index_count(root):
            return 0
        albums = []
        for key, _mtime, album in await store.load_library_cache(root, SCAN_FORMAT):
            relative = library_relative(root, key) or album.get("path")
            if relative:
                albums.append({**album, "path": relative})
        if not albums:
            return 0
        written, _ = await store.index_reconcile(root, albums)
        if written:
            logger.info(f"store index: recorded {written} album(s) from the saved library scan")
        return written
    except Exception as e:
        logger.error(f"could not fill the store index from the saved scan: {e}")
        return 0


# ---------------------------------------------------------------- the checks

def audio_tracks(release: dict) -> list[dict]:
    """
    The release's tracks that arrive as audio. A track on a video medium (DVD-Video, Blu-ray) or
    of a video recording is marked `video` by both payload builders, and never arrives as a
    file: counted, a CD+DVD pressing held whole could never be complete. A release that is ALL
    video (a concert film) keeps every track: whatever audio of it someone shares is all there
    is to compare, and with nothing left anything held would read as the whole of it.
    """
    tracks = release.get("tracks") or []
    audio = [track for track in tracks if not track.get("video")]
    return audio or tracks


def _look(folder: Path, release_mbid: str) -> dict | None:
    """
    What is in this folder now: None when it is gone (or holds no audio any more), else whether
    its first audio file is tagged with this release, and every audio file's folded title and
    (disc, track) as filing reads them (organizer.existing_tracks: its tags, then deadwax's
    "NN - Title" name) - no more than filing's own duplicate check reads.
    """
    if not folder.is_dir():
        return None
    tracks = existing_tracks(folder)
    if not tracks:
        return None
    return {
        "tagged": read_album_mbid(folder) == release_mbid,
        "files": tracks,
        "formats": {file_extension(track["name"]) for track in tracks},
    }


def held_tracks(release: dict, files: list[dict]) -> tuple[int, int, bool]:
    """
    (the release's tracks these files hold, its audio tracks, whether that is all of them).

    **By title first.** A wanted track is held when some file's folded title is its title and no
    other track of the release shares that title. Numbers are the weaker witness: beets numbers a
    set across discs by default, deadwax filed sets with running numbers and no disc tags before
    v0.6.5, and a stray disc tag moves a track - each made a whole album read as part held. Only a
    track whose title is shared, or that no file's title names, is placed by number: its
    (disc, track) as filing numbers it (organizer.planned_key), else its running position (on the
    file's disc 1, or its own disc). A file a title has already placed never stands in for
    another track by number, nor does one titled as another track of the release.

    Each wanted track counts once, however many files hold it: two formats, two copies, count
    once. With no tracklist at all, whatever is there is all of it, counted as distinct tracks.
    Files with neither a title nor a number are counted by name when nothing else can be read.
    """
    wanted = audio_tracks(release)
    if not wanted:
        distinct = {file["title"] or file["key"] or Path(file["name"]).stem for file in files}
        return len(distinct), 0, True

    if not any(file["title"] or file["key"] for file in files):
        count = min(len({Path(file["name"]).stem for file in files}), len(wanted))
        return count, len(wanted), count >= len(wanted)

    titles = [normalize(track.get("title") or "") for track in wanted]
    wanted_titles = set(titles) - {""}
    shared = {title for title, count in Counter(titles).items() if count > 1}
    #? titles a file places: a track's, and no other track's too
    placed = {file["title"] for file in files if file["title"] in wanted_titles - shared}

    held = 0
    for track, title in zip(wanted, titles):
        if title in placed:
            held += 1
            continue
        key, position, disc = planned_key(release, track), track.get("position"), track.get("disc") or 1
        for file in files:
            #? no number, or titled as another of the release's tracks - it is that one, not this
            if file["key"] is None or (file["title"] and file["title"] != title and file["title"] in wanted_titles):
                continue
            if file["key"] == key or (position and file["key"][1] == position and file["key"][0] in (1, disc)):
                held += 1
                break
    return held, len(wanted), held == len(wanted)


async def held_copy(store, root: str, release_mbid: str | None, release: dict | None = None) -> dict | None:
    """
    This pressing as the library holds it, looked at on disk - or None.

    Over every folder indexed as the release that passes the look (a release stored one folder
    per disc is several rows), what is held is the release's DISTINCT tracks (held_tracks) - not
    audio files. Counting files let the same tracks twice (a FLAC and an MP3 side by side, two
    part copies, an interview track) read as a complete pressing and refuse the download of the
    tracks nobody had (step 2 review). Video tracks don't count (audio_tracks).

    A folder that has gone is marked `missing`; one whose first file isn't tagged with this
    release - a folder shared with an untagged rip - simply doesn't count, and the download goes
    ahead for filing's duplicate rules to sort out.
    """
    if not _usable(store) or not root or not release_mbid:
        return None
    release = release or {}
    try:
        rows = await store.index_present(root, release_mbid)
        if not rows:
            return None
        looks = await asyncio.to_thread(lambda: [_look(Path(root) / row["path"], release_mbid) for row in rows])

        verified = []
        for row, look in zip(rows, looks):
            if look is None:
                await store.index_gone(root, row["path"], "missing")
            elif look["tagged"]:
                verified.append((row, look))
        if not verified:
            return None

        count, expected, complete = held_tracks(release, [file for _, look in verified for file in look["files"]])
        first = verified[0][0]
        return {
            "path": first["path"],
            "paths": [row["path"] for row, _ in verified],
            "artist": first.get("artist") or "",
            "album": first.get("album") or "",
            "edition": first.get("edition") or "",
            #? distinct tracks of the release held (of any, with no tracklist to hold them to)
            "track_count": count,
            #? the release's AUDIO tracks, 0 with no tracklist
            "expected_tracks": expected,
            "formats": sorted(set().union(*(look["formats"] for _, look in verified))),
            "complete": complete,
            #? for a part held: whether a download would be filed INTO one of these folders, and
            #? where it would go - filled in by Find (filing_folder), which alone needs to know
            "fills_gaps": False,
            "filed_to": None,
        }
    except Exception as e:
        logger.warning(f"could not check the library for {release_mbid}: {e}")
        return None


def _filing_folder(root: str, release: dict) -> str | None:
    target, _ = resolve_album_dir(root, release, quiet=True)
    return library_relative(root, target)


async def filing_folder(root: str, release: dict) -> str | None:
    """
    The album folder a download of this release would be filed into, relative to the library -
    worked out by filing's own resolve_album_dir, so it can't disagree with it - or None.

    Only that folder is ever filled in: filing skips tracks already THERE (find_duplicate), and
    never looks in any other folder of the release. A part held in a folder named some other
    way (Picard's `Artist/Album`, an old template, a country suffix before v0.8.3, an artist's
    old name) gets a whole second copy beside it, and Find must not promise otherwise. (Compared
    as path strings: on a case-insensitive disk a differently cased folder is the same one, and
    the note then says "separately" when it isn't - a documented limit, the safe direction.)
    """
    if not root:
        return None
    try:
        return await asyncio.to_thread(_filing_folder, root, release)
    except Exception as e:
        logger.warning(f"could not work out where {release.get('album')} would be filed: {e}")
        return None


async def other_pressings(store, root: str, release_group_mbid: str | None,
                          release_mbid: str | None) -> list[dict]:
    """
    The album's OTHER pressings the library holds - same release group, another release id - one
    per folder that is still there. A note, not a verdict: nothing is refused for them.
    """
    if not _usable(store) or not root or not release_group_mbid:
        return []
    try:
        rows = await store.index_pressings(root, release_group_mbid, release_mbid)
        there = await asyncio.to_thread(lambda: [(Path(root) / row["path"]).is_dir() for row in rows])
        found = []
        for row, present in zip(rows, there):
            if not present:
                await store.index_gone(root, row["path"], "missing")
                continue
            found.append({
                "path": row["path"],
                "release_mbid": row.get("release_mbid"),
                "edition": row.get("edition") or "",
                "year": row.get("year") or "",
                "track_count": row.get("track_count") or 0,
                "formats": row.get("formats") or [],
            })
        return found
    except Exception as e:
        logger.warning(f"could not look for other pressings of {release_group_mbid}: {e}")
        return []


async def in_flight(store, release_mbid: str | None, excluding_job_id: int | None = None,
                    release: dict | None = None, whole: bool = True) -> dict | None:
    """
    A job already bringing this release in (store.in_flight_job), or None. `whole` asks for one
    bringing the WHOLE pressing - fetching at least as many files as the release has audio
    tracks - which is what stops Find and refuses a download; `whole=False` for any, for the note
    that a download of part of it is running. A `complete` job only counts while organizing is on.
    """
    if not _usable(store) or not release_mbid:
        return None
    covering = len(audio_tracks(release or {})) if whole else 0
    try:
        return await store.in_flight_job(release_mbid, excluding_job_id, filing=Config.organizing_enabled(),
                                         covering=covering)
    except Exception as e:
        logger.warning(f"could not look for a download of {release_mbid} in flight: {e}")
        return None


#? a job past downloading, on its way into the library - nothing left to cancel for another peer
FILING_STATUSES = ("organizing", "complete")


def describe_job(job: dict) -> dict:
    """What Find says about a download already in flight - the panel adds how far it has got."""
    return {
        "job_id": job.get("id"),
        "status": job.get("status"),
        "username": job.get("username") or "",
        "files": len(job.get("files") or []),
    }


async def already_have(store, release: dict, excluding_job_id: int | None = None) -> str | None:
    """
    Why a download of this release shouldn't start - the whole pressing is downloading already,
    or the library holds all of it - or None to go ahead. For /enqueue and the retries, under
    release_lock. A job for PART of it (a lone disc folder) refuses nothing: it will never bring
    the rest. A release with no release id is never checked, as before any of this existed.
    """
    release_mbid = (release.get("release_mbid") or "").strip()
    if not release_mbid:
        return None
    try:
        job = await in_flight(store, release_mbid, excluding_job_id, release)
        if job is not None:
            peer = job.get("username") or "another peer"
            if job.get("status") in FILING_STATUSES:
                return f"already downloaded from {peer}, and being filed now"
            return f"already downloading from {peer}"
        held = await held_copy(store, Config.LIBRARY_PATH or "", release_mbid, release)
        if held is not None and held["complete"]:
            return f"already in your library: {held['path']}"
    except Exception as e:
        logger.warning(f"could not check whether {release_mbid} is already here: {e}")
    return None


# ---------------------------------------------------------------- one at a time

#? key -> [its lock, how many hold it or wait for it]. Counted so a lock goes the moment nobody
#? needs it: a lock per release ever downloaded, kept for the life of the process, is a dict
#? that only grows (routes/library.py's _APPLY_LOCKS does exactly that, one per album).
_RELEASE_LOCKS: dict[str, list] = {}


@asynccontextmanager
async def release_lock(key: str | None):
    """
    One download of a release at a time: held across the check, slskd's enqueue and recording
    the job, so two clicks, two tabs, or a retry racing a new download can't both get past the
    check before either has a job to be seen by. Keyed on the release id - or, for the retries
    of a job with none, on the job (`job:<id>`), so its re-read under the lock still stops two
    retries of it at once. No key, no lock.
    """
    key = (key or "").strip()
    if not key:
        yield
        return

    entry = _RELEASE_LOCKS.get(key)
    if entry is None:
        entry = _RELEASE_LOCKS[key] = [asyncio.Lock(), 0]
    entry[1] += 1
    try:
        async with entry[0]:
            yield
    finally:
        entry[1] -= 1
        if not entry[1] and _RELEASE_LOCKS.get(key) is entry:
            del _RELEASE_LOCKS[key]
