"""
Turning a finished slskd download into a tagged, filed album.

This is the only part of deadwax that writes to the user's filesystem, so it is built in
two halves that are deliberately kept apart:

  plan_organization()  - pure. Works out what *would* happen. No disk writes, fully testable.
  execute_plan()       - does it, and only what the plan says.

That split is what makes dry-run trustworthy rather than a second code path that might
disagree with the real one: dry-run runs the identical plan and simply declines to execute.

Defaults are cautious on purpose - copy rather than move, never overwrite, and ORGANIZE_MODE
starts at dry_run so a first deploy with a mis-mapped volume reports what it would have done
instead of scattering a music library.
"""

import asyncio
import os
import re
import shutil
import time
from pathlib import Path

from src.editions import edition_discriminator, resolve_edition_label
from src.naming import DEFAULT_ALBUM_FOLDER, render_album_folder, validate_template
from src.logger import logger
from src.matching import (AUDIO_EXTENSIONS, file_extension, match_tracks_to_files, normalize,
                          split_remote_path)


#? off      - never organize, downloads just sit in slskd's folder
#? dry_run  - plan and log, touch nothing (default: safe first deploy)
#? copy     - copy into the library, leave slskd's copy alone
#? move     - move into the library
ORGANIZE_MODES = ("off", "dry_run", "copy", "move")

INVALID_FILENAME_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')

#? Non-audio files worth carrying into the library alongside the tracks. Cover art especially -
#? leaving it behind in slskd's folder loses it, since only audio is ever enqueued explicitly.
COMPANION_EXTENSIONS = {
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "cue", "log", "nfo", "txt", "m3u", "m3u8", "sfv"
}


def sanitize_filename(name: str, fallback: str = "unknown") -> str:
    """Make a string safe as a single path component on any of the usual filesystems."""
    cleaned = INVALID_FILENAME_CHARS.sub("_", name or "").strip(" .")
    cleaned = re.sub(r"\s+", " ", cleaned)
    #? 255 is the common per-component limit; leave room for a numeric suffix
    return (cleaned[:200] or fallback)


def filed_artist(release: dict) -> str:
    """
    The artist folder an album is filed under: who it is BY, in their current name.

    Not the credit. A release is credited to whatever the artist was calling themselves that
    year - Ye's records say "Kanye West" until 2024 and "Ye" after - and filing by the credit
    gives one artist a folder per name. `album_artist` is the current name, sent by the browser
    from MusicBrainz's own `artist-credit[].artist.name`; a job queued before it existed has
    only `artist`, and files exactly where it always would have.

    The folder and the albumartist tag both come from here and must: the metadata queue's
    misfiled check compares one against the other, so moving only the folder would flag every
    album by everyone who has ever renamed.
    """
    return release.get("album_artist") or release.get("artist") or ""


def country_in_folder() -> bool:
    """
    Whether a release's country may name its folder - COUNTRY_IN_FOLDER, off unless set to "on".

    Read here, at the one place folder names are made, so the organizer, the metadata editor's
    preview and its write all agree. An unrecognised value is off: the default, and the one that
    writes less into somebody's folder names.
    """
    from src.config import Config
    return (Config.COUNTRY_IN_FOLDER or "off").strip().lower() == "on"


def album_folder_template() -> str:
    """
    ALBUM_FOLDER_TEMPLATE (v0.9.17), or the long-standing convention when it's unset or can't be
    used - read here, beside country_in_folder, at the one place folder names are made. An
    invalid template never names a folder: the settings tab refuses one on save, and one set in
    the environment is reported there and ignored here.
    """
    from src.config import Config

    template = (Config.ALBUM_FOLDER_TEMPLATE or "").strip()
    return template if template and validate_template(template) is None else DEFAULT_ALBUM_FOLDER


def build_album_dirname(release: dict, discriminator: str = "") -> str:
    """
    `Album (Year)`, plus ` [Edition]` when this release is a distinguishable edition - or
    whatever ALBUM_FOLDER_TEMPLATE says, which defaults to exactly that (src/naming.py).

    The suffix is omitted entirely for ordinary albums - most releases have exactly one
    edition and do not need decorating. It appears only when there is something real to say,
    which is what keeps the library readable while still letting the deluxe and the standard
    press of the same record coexist.

    `discriminator` is the escape hatch for two genuinely different releases that still
    produce the same name; plan_organization() supplies it only after seeing an actual
    collision on disk.
    """
    album = sanitize_filename(release.get("album"), "Unknown Album")

    #? The ALBUM's year, not this pressing's. A 2011 remaster of a 1975 record belongs in
    #? "Wish You Were Here (1975) [2011 remaster]" - the year identifies the album and the
    #? edition identifies the pressing, so putting the reissue year in front files the same
    #? record under two different decades depending on which copy you happened to get.
    #? MusicBrainz keeps this on the release GROUP as first-release-date. ({release_year} is
    #? there for a template that wants the pressing's year anyway.)
    year = (release.get("original_year") or release.get("year") or "").strip()

    def clean(value) -> str:
        text = str(value or "").strip()
        return sanitize_filename(text, "") if text else ""

    values = {
        "album": album,
        "year": clean(year),
        "release_year": clean((release.get("year") or "")[:4]),
        "edition": clean(resolve_edition_label(release, with_country=country_in_folder())),
        "artist": clean(filed_artist(release)),
        "format": clean(release.get("media_format")),
        "country": clean(release.get("country")),
        "catalog": clean(release.get("catalog_number")),
    }
    return sanitize_filename(render_album_folder(album_folder_template(), values, discriminator), album)


def build_target_path(
    library_root: str,
    release: dict,
    track: dict | None,
    extension: str,
    discriminator: str = "",
) -> Path:
    """
    {library}/{artist}/{album} ({year}) [{edition}]/{NN} - {title}.{ext}

    Tracks that couldn't be matched to the tracklist keep their original filename rather than
    being given a made-up number - a wrong track number is worse than none.
    """
    artist = sanitize_filename(filed_artist(release), "Unknown Artist")

    if track and track.get("position") and track.get("title"):
        filename = f"{int(track['position']):02d} - {sanitize_filename(track['title'])}.{extension}"
    else:
        filename = sanitize_filename(track.get("filename") if track else None, "untitled") + f".{extension}"

    return Path(library_root) / artist / build_album_dirname(release, discriminator) / filename


def find_local_file(download_root: str, remote_filename: str, remote_directory: str = "") -> Path | None:
    """
    Locate what slskd actually wrote to disk for a given remote file.

    slskd's on-disk layout isn't something we control or can rely on staying put (it has
    changed between versions, and sanitizes remote directory names), so rather than
    reconstructing the path we search for the basename under the download root and prefer the
    hit whose folders match the remote ones. Slower, but it survives slskd reorganizing its own
    downloads directory.

    The folders are the FILE's own, not the job's: slskd names a download's folder after the
    folder the file sat in on the peer's share (its `{source_directory}` pattern, the default)
    or after the whole remote path. For a set shared one folder per disc (v1.0.1) the job's
    directory is the album folder while each file sits in its "CD 1" or "CD 2", and both discs
    can hold an `01 - Wish You Were Here.flac`. The hit agreeing on the most folders, counted up
    from the file, wins; that is one folder under the default pattern and more under the full one.
    """
    root = Path(download_root)
    if not root.is_dir():
        return None

    own_directory, basename = split_remote_path(remote_filename)
    if not basename:
        return None

    matches = [p for p in root.rglob(basename) if p.is_file()]

    if len(matches) < 2:
        return matches[0] if matches else None

    remote_folders = [f for f in (own_directory or remote_directory).replace("\\", "/").split("/") if f]

    def agreement(path: Path) -> int:
        count = 0
        for local, remote in zip(reversed(path.parent.relative_to(root).parts), reversed(remote_folders)):
            if local != remote:
                break
            count += 1
        return count

    #? max() keeps the first of equals, which is what this always returned with nothing to go on
    return max(matches, key=agreement)


def is_within(child: Path, parent: Path) -> bool:
    """
    True only if `child` really sits underneath `parent`.

    Guards the one genuinely destructive operation in here - removing a source directory.
    Resolving both sides first means a symlink or a ".." in a configured path can't be used
    to walk the delete outside slskd's download folder.
    """
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except (ValueError, OSError):
        return False


def find_companion_files(source_dir: Path, placed: set[str]) -> list[Path]:
    """Art and sidecar files sitting next to the tracks, which are worth keeping."""
    if not source_dir.is_dir():
        return []

    return [
        entry for entry in sorted(source_dir.iterdir())
        if entry.is_file()
        and entry.name not in placed
        and file_extension(entry.name) in COMPANION_EXTENSIONS
    ]


def read_album_mbid(directory: Path) -> str | None:
    """
    The MusicBrainz release id already filed in this folder, if any.

    Identity rather than appearance: two releases are the same edition when they share a
    release MBID, whatever their folders happen to be called. Reads the first audio file it
    can and stops - every track in a folder belongs to the same release, so there is nothing
    to gain from opening the rest.

    Returns None for a folder deadwax didn't organize (no MBID tag), which the caller must
    treat as "unknown", NOT as "different" - guessing wrong there would fork someone's
    existing library into duplicate folders.
    """
    import mutagen

    if not directory.is_dir():
        return None

    for entry in sorted(directory.iterdir()):
        if not entry.is_file() or not file_extension(entry.name) in AUDIO_EXTENSIONS:
            continue

        try:
            audio = mutagen.File(str(entry), easy=True)
        except Exception:
            continue

        if audio is None:
            continue

        values = audio.get("musicbrainz_albumid") or []
        if values:
            return str(values[0]).strip() or None

        #? a readable audio file that simply has no MBID tag is answer enough - the folder
        #? wasn't organized by us, so stop rather than opening every track hoping otherwise
        return None

    return None


def _track_key(disc, number) -> tuple[int, int] | None:
    """A track's place as (disc, number), disc 1 when untagged. None when the number is unknown."""
    track = _disc_number(number)  # same parsing: '3', '03' and '3/12' are all 3
    if track is None:
        return None
    return (_disc_number(disc) or 1, track)


#? "NN - Title.ext", the name deadwax gives a matched track - the fallback when a file's tags
#? can't be read
_NUMBERED_NAME = re.compile(r"^(\d{1,3}) - ")


def _read_track(path: Path) -> tuple[tuple[int, int] | None, str]:
    """
    Where a file sits in its album and what it's called: ((disc, track) or None, folded title).
    From its own tags, with deadwax's "NN - Title.ext" name as the fallback for either.
    """
    import mutagen

    key, title = None, ""
    try:
        audio = mutagen.File(str(path), easy=True)
    except Exception:
        audio = None
    if audio is not None:
        try:
            key = _track_key((audio.get("discnumber") or [None])[0], (audio.get("tracknumber") or [None])[0])
            title = str((audio.get("title") or [""])[0])
        except Exception:
            pass
    named = _NUMBERED_NAME.match(path.name)
    if key is None and named:
        key = (1, int(named.group(1)))
    #? only deadwax's own naming says what a track is called - "01.flac" or "Track 04.mp3" name
    #? nothing, and two of them would otherwise "match" on a meaningless stem
    if not title and named:
        title = Path(path.name[named.end():]).stem
    return key, normalize(title)


def existing_tracks(directory: Path) -> list[dict]:
    """Every audio file already in this folder: its place, folded title and filename."""
    if not directory.is_dir():
        return []
    found = []
    for entry in sorted(directory.iterdir()):
        if entry.is_file() and file_extension(entry.name) in AUDIO_EXTENSIONS:
            key, title = _read_track(entry)
            found.append({"key": key, "title": title, "name": entry.name})
    return found


def _planned_track(release: dict, track: dict | None, source: Path) -> tuple[tuple[int, int] | None, str]:
    """
    Where an incoming file will sit and what it's called. A matched track says so itself,
    numbered exactly as tag_values numbers it (per disc on a multi-disc release, running
    otherwise). An unmatched file - every file of a grab made without a tracklist - is asked its
    own tags.
    """
    if track and track.get("position"):
        if _is_multi_disc(release) and track.get("disc") and track.get("disc_position"):
            key = (int(track["disc"]), int(track["disc_position"]))
        else:
            key = (1, int(track["position"]))
        return key, normalize(track.get("title") or "")
    return _read_track(source)


def find_duplicate(existing: list[dict], key, title: str, same_release: bool) -> str | None:
    """
    The file already in the folder that this incoming track would duplicate, or None.

    Holding the SAME release, the folder's numbering is the release's, so (disc, track) says
    which song it is. Otherwise - an untagged folder resolve_album_dir chose to share, or a job
    naming no release - numbers mean nothing across pressings (a 10-track and an 11-track CD
    disagree from the bonus track on), so only the same title counts, on the same disc when both
    are known. An unknown title is never a duplicate.
    """
    if same_release and key is not None:
        for entry in existing:
            if entry["key"] == key:
                return entry["name"]
        return None
    if not title:
        return None
    for entry in existing:
        if entry["title"] == title and (key is None or entry["key"] is None or entry["key"][0] == key[0]):
            return entry["name"]
    return None


def resolve_album_dir(library_root: str, release: dict) -> tuple[Path, str]:
    """
    Where this release's folder should be, avoiding a different release's folder.

    The ordinary case resolves on the first try. The interesting case is two releases whose
    names collide anyway - the same album, year and disambiguation, differing only by
    pressing - where we escalate to the catalogue number or the release id rather than
    letting one silently overwrite (or, as before, be silently skipped against) the other.

    Crucially this does NOT treat an untagged folder as a collision. A library that predates
    deadwax has no MBIDs, and forking every one of those albums into a second folder would
    be far worse than sharing one.
    """
    artist = sanitize_filename(filed_artist(release), "Unknown Artist")
    artist_dir = Path(library_root) / artist
    wanted_mbid = (release.get("release_mbid") or "").strip()

    for discriminator in ("", edition_discriminator(release)):
        candidate = artist_dir / build_album_dirname(release, discriminator)

        if not candidate.exists():
            return candidate, discriminator

        existing = read_album_mbid(candidate)

        #? free to share the folder: either it is demonstrably the same release, or it is
        #? untagged and we have no business assuming otherwise
        if existing is None or not wanted_mbid or existing == wanted_mbid:
            return candidate, discriminator

        if not discriminator:
            logger.info(
                f"'{candidate.name}' already holds a different release, "
                f"filing this edition separately",
                extra={"frontend": True, "src": "slskd"},
            )

    #? both attempts are taken by other releases, which needs the release id to break
    fallback = artist_dir / build_album_dirname(release, wanted_mbid[:8] or "alt")
    return fallback, wanted_mbid[:8] or "alt"


def plan_organization(job: dict, download_root: str, library_root: str) -> dict:
    """
    Work out every file operation this job implies. Touches nothing.

    The file->track mapping is recomputed here from the stored release and file list rather
    than having been persisted at match time: match_tracks_to_files is pure and needs only
    filenames, so recomputing keeps one source of truth instead of storing derived data that
    could drift from the code that produced it.
    """
    release = job.get("release") or {}
    tracks = release.get("tracks") or []
    files = job.get("files") or []

    mapping = match_tracks_to_files(tracks, files) if tracks else {}
    track_by_filename = {
        entry["file"]["filename"]: entry["track"] for entry in mapping.values()
    }

    #? decided once for the whole job, so every track lands in the same folder even if the
    #? escalation kicked in - resolving per file could split an album across two directories
    album_target, discriminator = resolve_album_dir(library_root, release)

    #? What's already in that folder, by disc and track. resolve_album_dir shares a folder that
    #? holds this same release (or an untagged one), and filing a second copy into it used to put
    #? a FLAC and an MP3 of every track side by side - one album, each track twice, for everyone
    #? who plays the library (v1.0.1). A track already present is skipped; a missing one still
    #? files, so a download can fill the gaps a partial one left.
    already_here = existing_tracks(album_target)
    wanted_mbid = (release.get("release_mbid") or "").strip()
    same_release = bool(already_here and wanted_mbid and read_album_mbid(album_target) == wanted_mbid)

    operations = []
    problems = []
    used_targets: set[Path] = set()

    for file_entry in files:
        remote_filename = file_entry.get("filename", "")
        source = find_local_file(download_root, remote_filename, job.get("directory", ""))

        if source is None:
            problems.append(f"not found on disk: {remote_filename}")
            continue

        _, basename = split_remote_path(remote_filename)
        track = track_by_filename.get(remote_filename)
        extension = file_extension(basename) or "bin"

        target = build_target_path(
            library_root,
            release,
            track or {"filename": Path(basename).stem},
            extension,
            discriminator,
        )

        #? two source files resolving to one target would silently destroy one of them
        if target in used_targets:
            problems.append(f"two files map to the same destination: {target.name}")
            continue

        used_targets.add(target)
        operation = {
            "source": str(source),
            "target": str(target),
            "track": track,
            "exists": target.exists(),
        }
        if already_here:
            key, title = _planned_track(release, track, source)
            duplicate = find_duplicate(already_here, key, title, same_release)
            if duplicate:
                operation["duplicate_of"] = duplicate
        operations.append(operation)

    album_dir = Path(operations[0]["target"]).parent if operations else None

    #? Carry cover art and sidecars across too. They're never enqueued (only audio is), so if
    #? slskd happened to fetch them they'd otherwise be stranded - and leaving anything behind
    #? means the source folder can never be tidied up either.
    source_dirs = {Path(op["source"]).parent for op in operations}
    placed_names = {Path(op["source"]).name for op in operations}
    companions = []

    #? A log, cue or scan beside a copy that isn't being filed describes THAT copy, not the one
    #? already in the folder - so when the folder already had any of these tracks, the sidecars
    #? stay in slskd's folder with the duplicates. Carrying them across also made an all-duplicate
    #? job count as "organized", as if the album had arrived (v1.0.2).
    if any(op.get("duplicate_of") for op in operations):
        album_dir_for_companions = None
    else:
        album_dir_for_companions = album_dir

    if album_dir_for_companions is not None:
        for source_dir in sorted(source_dirs):
            for companion in find_companion_files(source_dir, placed_names):
                target = album_dir / sanitize_filename(companion.name, companion.name)
                if target in used_targets:
                    continue
                used_targets.add(target)
                companions.append({
                    "source": str(companion),
                    "target": str(target),
                    "track": None,
                    "companion": True,
                    "exists": target.exists(),
                })

    return {
        "job_id": job.get("id"),
        "album_dir": str(album_dir) if album_dir else None,
        "operations": operations + companions,
        "companion_count": len(companions),
        "source_dirs": sorted(str(d) for d in source_dirs),
        "problems": problems,
        "matched_tracks": len(mapping),
        "total_tracks": len(tracks),
    }


def _is_multi_disc(release: dict) -> bool:
    """True when the release's tracklist spans more than one disc."""
    return len({t.get("disc") for t in release.get("tracks") or [] if t.get("disc")}) > 1


def _disc_number(value) -> int | None:
    """A disc tag as a number - '2', '02' and '2/3' all mean disc 2. None when absent or unreadable."""
    head = str(value or "").split("/")[0].strip()
    try:
        return int(head)
    except ValueError:
        return None


def _mbids(value) -> str | list[str] | None:
    """
    One id as a string, several as a list.

    Vorbis comments and ID3 both hold several values under one key, and a credit to two artists
    is exactly that - two values. Keeping a single id a plain string matters for the retag
    preview, which compares what a file carries against what it would carry: a bare string on
    one side and a one-item list on the other would report a change nobody made, forever.
    """
    if not value:
        return None

    ids = [str(v) for v in (value if isinstance(value, list) else [value]) if v]
    if not ids:
        return None

    return ids[0] if len(ids) == 1 else ids


def tag_values(release: dict, track: dict | None, current: dict | None = None) -> dict:
    """
    The tags a file should carry for this release and track.

    Split out from write_tags() so the retag preview can show what applying a release WOULD
    change without duplicating the rules. Two copies of this would drift, and a preview that
    disagrees with the write it is previewing is worse than no preview - the same reason
    dry-run runs the identical plan rather than a parallel one.

    `current` is what the file carries now, as far as the caller has read it. Only one rule
    depends on it - a stray disc number, below - and both callers pass the same reading of the
    same file, so the preview and the write still cannot disagree.
    """
    values = {
        "album": release.get("album"),
        #? Who the album is BY, in their current name - the same string that names its folder,
        #? which is what lets one artist be one artist in every player that groups on this tag.
        #? See filed_artist().
        "albumartist": filed_artist(release) or None,
        #? AS CREDITED - what the sleeve says. Overridden below by the TRACK's own credit where
        #? it has one, which on an ordinary album is every track.
        "artist": release.get("artist"),
        #? Who this is, in MusicBrainz's terms, which is the one part of a credit that survives
        #? somebody renaming a band. deadwax already wrote the release and release-group ids
        #? and not these, so nothing it filed could say who the artist WAS - which is also why
        #? the artist page has to fall back to searching by name.
        "musicbrainz_albumartistid": _mbids(release.get("artist_mbids")),
        "musicbrainz_artistid": _mbids(release.get("artist_mbids")),
        "date": release.get("year"),
        #? Picard's convention, and the reason the folder can say 1975 while the file still
        #? records that this particular copy is the 2011 press. Not every container accepts
        #? it (easy MP4 doesn't) and the loop below skips whatever is rejected.
        "originaldate": release.get("original_year"),
        #? the edition's identity, and the only one of these every container supports. The
        #? library scanner groups on it: two folders sharing an MBID are the same edition
        #? however they happen to be named, and that is what survives someone renaming a
        #? folder by hand.
        "musicbrainz_albumid": release.get("release_mbid"),
        #? these feed resolve_edition_label() if the edition ever has to be recomputed from
        #? disk. Not universally supported - the loop below skips whatever a container
        #? rejects, which is why the MBID above carries the identity on its own.
        "musicbrainz_releasegroupid": release.get("release_group_mbid"),
        "releasecountry": release.get("country"),
        "media": release.get("media_format"),
        "catalognumber": release.get("catalog_number"),
    }

    if track:
        values["title"] = track.get("title")

        #? A track credited to somebody else keeps its own artist - a split release, a
        #? compilation, a guest spot. Until now every track was given the RELEASE's artist,
        #? so applying a release to a compilation rewrote eighteen different artists into
        #? one. albumartist stays the release's credit, which is what the two tags are for.
        if track.get("artist"):
            values["artist"] = track["artist"]
        if track.get("artist_mbids"):
            values["musicbrainz_artistid"] = _mbids(track["artist_mbids"])

        #? A multi-disc release is numbered PER DISC, the way MusicBrainz and every player number
        #? it: disc 2 opens with track 1 of disc 2, not track 11 of one running sequence.
        #? `position` stays the running number regardless - the matcher keys on it and files are
        #? named after it, which is what keeps a two-disc set in order inside one folder.
        #?
        #? A single-disc release writes no disc tag at all. Writing "1" everywhere would give
        #? every album in the library a discnumber change, so re-opening the editor on an album
        #? that is already right could never again say "nothing to change".
        multi_disc = _is_multi_disc(release)

        if multi_disc and track.get("disc") and track.get("disc_position"):
            values["tracknumber"] = str(track["disc_position"])
            values["discnumber"] = str(track["disc"])
        elif track.get("position"):
            values["tracknumber"] = str(track["position"])

        #? A single-disc release IS disc 1, and usually nothing needs writing to say so: a file
        #? with no disc tag already reads as disc 1 everywhere, and writing "1" into every album
        #? would give each of them a diff forever (above). But a file that claims to be on some
        #? OTHER disc is wrong, and applying the release is exactly the moment to put it right -
        #? without this, re-applying the correct release could never undo a wrong one. That is
        #? how Jackpot Juicer's opening track was found: alone on "disc 2" of a one-disc album,
        #? with nothing re-applying the album could do about it.
        if not multi_disc and _disc_number((current or {}).get("discnumber")) not in (None, 1):
            values["discnumber"] = "1"

    #? empty values are dropped rather than written as blanks - clearing a tag the user
    #? already has because MusicBrainz didn't supply one would be destructive. A list is left
    #? as a list: several artist ids are several values, not one string with commas in it.
    return {
        key: (value if isinstance(value, list) else str(value))
        for key, value in values.items() if value
    }


def write_tags(path: Path, release: dict, track: dict | None, drop_stale_release_id: bool = False) -> None:
    """
    Tag the file from the MusicBrainz release it came from.

    Writes the MusicBrainz IDs too, so the resulting library stays legible to Picard/beets
    later instead of being a deadwax-only artifact. Tagging failures are logged and
    tolerated: a filed-but-untagged file is a far better outcome than a half-organized album.
    """
    import mutagen

    try:
        audio = mutagen.File(str(path), easy=True)
    except Exception as e:
        logger.warning(f"could not read tags on {path.name}: {e}")
        return

    if audio is None:
        logger.warning(f"unsupported audio format for tagging: {path.name}")
        return

    #? the one thing tag_values needs to know about the file as it stands - see the disc rule
    try:
        current_disc = str((audio.get("discnumber") or [""])[0])
    except Exception:
        current_disc = ""

    for key, value in tag_values(release, track, {"discnumber": current_disc}).items():
        if not value:
            continue

        try:
            audio[key] = value if isinstance(value, list) else str(value)
        except Exception:
            #? not every container supports every key (easy mp4 is picky); skip rather than abort
            continue

    #? A DOWNLOAD that names no release (a group-level grab when MusicBrainz couldn't list the
    #? pressings) must not keep the release id the SHARER's tagger wrote (v1.0.1): tag_values skips
    #? an empty value, so it would survive and claim a pressing nobody chose - and the scan and the
    #? "already held" checks trust that tag. Filing only: the metadata editor shares write_tags,
    #? and a retag naming no release must leave the file's own id alone, as its preview says.
    if drop_stale_release_id and not release.get("release_mbid"):
        try:
            if "musicbrainz_albumid" in audio:
                del audio["musicbrainz_albumid"]
        except Exception:
            pass

    try:
        audio.save()
    except Exception as e:
        logger.warning(f"could not write tags to {path.name}: {e}")


def execute_plan(plan: dict, release: dict, mode: str = "dry_run") -> dict:
    """
    Carry out a plan. `mode` decides how far it goes; dry_run stops before touching anything.
    """
    if mode not in ORGANIZE_MODES:
        mode = "dry_run"

    results = {"organized": 0, "skipped": 0, "duplicates": 0, "failed": 0,
               "dry_run": mode == "dry_run", "mode": mode}

    if mode == "off":
        return results

    for operation in plan["operations"]:
        source = Path(operation["source"])
        target = Path(operation["target"])

        #? the album already has this track, perhaps in another format - a second copy beside it
        #? would show every track twice. It stays in slskd's folder, and counts as skipped so the
        #? move's clean-up keeps that folder rather than deleting unfiled music.
        if operation.get("duplicate_of"):
            logger.info(
                f"{'[dry run] ' if mode == 'dry_run' else ''}already in the store as "
                f"{operation['duplicate_of']}, not filing {source.name} beside it"
            )
            results["skipped"] += 1
            results["duplicates"] += 1
            continue

        if mode == "dry_run":
            logger.info(f"[dry run] would place {source.name} -> {target}")
            results["organized"] += 1
            continue

        #? never clobber. An existing destination is far more likely to be a real album the
        #? user already has than something safe to overwrite.
        if target.exists():
            logger.warning(f"already exists, leaving it alone: {target}")
            results["skipped"] += 1
            continue

        try:
            target.parent.mkdir(parents=True, exist_ok=True)

            if mode == "move":
                shutil.move(str(source), str(target))
            else:
                shutil.copy2(str(source), str(target))

            if not operation.get("companion"):
                write_tags(target, release, operation.get("track"), drop_stale_release_id=True)

            results["organized"] += 1

        except Exception as e:
            logger.error(f"failed to place {source.name}: {e}")
            results["failed"] += 1

    return results


def cleanup_source_dirs(plan: dict, download_root: str, results: dict) -> list[str]:
    """
    Remove the slskd folders a completed move emptied of music.

    Every guard here is deliberate, because this is the only code in deadwax that deletes
    anything:

      - move only. copy exists precisely to leave the original alone.
      - nothing failed or was skipped, so we never delete beside a half-finished job.
      - the directory must resolve to somewhere inside the download root, so a stray path or
        symlink can't walk the delete out into the wider filesystem.
      - never the download root itself.
      - NO AUDIO ANYWHERE BENEATH IT. That is the guard that replaced `rmdir` (v0.6.20, asked
        for: "I'd like the album folder to be deleted when the songs are"). rmdir refuses a
        non-empty folder by construction, which kept every share that came with a Thumbs.db, a
        .md5 or a Scans/ folder - the tracks gone, the folder left for ever. Deleting whatever
        is left is what was wanted; deleting audio is not, and audio left here is somebody
        else's: a second job still downloading into the same peer folder, or files of it that
        nobody asked for. Those are kept and reported exactly as before.

    Note the sidecars worth having are already in the library by now - art, cue, log, nfo, txt,
    m3u and sfv are moved with the tracks (COMPANION_EXTENSIONS). What a delete here takes is
    the remainder, and it is named in the log so it is not taken silently.
    """
    if results.get("failed") or results.get("skipped"):
        return []

    root = Path(download_root)
    removed = []

    for raw in plan.get("source_dirs", []):
        directory = Path(raw)

        if not directory.is_dir():
            continue

        if directory.resolve() == root.resolve() or not is_within(directory, root):
            logger.warning(f"refusing to remove {directory}, it is not inside {download_root}")
            continue

        held_audio = [
            entry for entry in directory.rglob("*")
            if entry.is_file() and file_extension(entry.name) in AUDIO_EXTENSIONS
        ]

        if held_audio:
            logger.warning(
                f"left {directory.name} in place, it still holds "
                f"{len(held_audio)} track(s) nothing filed",
                extra={"frontend": True, "src": "slskd"},
            )
            continue

        leftovers = sorted(entry.name for entry in directory.iterdir())

        try:
            shutil.rmtree(directory)
            removed.append(str(directory))

            if leftovers:
                #? said out loud: these were deleted, not carried into the library
                logger.info(
                    f"removed {directory.name} and the {len(leftovers)} non-audio file(s) left "
                    f"in it: {', '.join(leftovers[:6])}",
                    extra={"frontend": True, "src": "slskd"},
                )
            else:
                logger.info(f"removed empty download folder {directory.name}")

        except OSError as e:
            logger.warning(
                f"left {directory.name} in place, it could not be removed: {e}",
                extra={"frontend": True, "src": "slskd"},
            )

    return removed


#? a folder touched more recently than this is left alone - see remove_empty_incomplete_dirs
EMPTY_DIR_MIN_AGE_SECONDS = 600


def remove_empty_incomplete_dirs(incomplete_root: str, now: float | None = None,
                                 min_age: float = EMPTY_DIR_MIN_AGE_SECONDS) -> list[str]:
    """
    Remove EMPTY folders from slskd's incomplete folder. Returns the ones removed.

    James: "there seem to be a lot of empty folders in /downloads/incomplete, but I'm not sure
    why they weren't deleted". Read in slskd's source: a download is written to
    `<incomplete>/<username>/<remote path>/<file>`, with every level created for it, and when it
    finishes FileService.MoveFile(deleteSourceDirectoryIfEmptyAfterMove: true) deletes the ONE
    folder the file sat in, if empty. Every level above it - the username, each folder of the
    peer's share path - is left behind, empty, for every download ever completed. deadwax's own
    cancel cleanup only ever tidied above a partial it had removed.

    Nothing here can delete a file: rmdir refuses a folder with anything in it, and the walk
    never follows a link. Two more guards:

    - never the root itself, which is slskd's configured folder;
    - never a folder modified in the last `min_age` seconds. slskd creates a download's folders
      and then opens its file inside them, and an rmdir landing between the two would fail that
      download. A new download's folder is new by definition, so it is always too young here.
      The ages are read BEFORE anything is removed: removing a child moves its parent's mtime,
      and judging the parent by that would stop the sweep one level up every time.
    """
    root = Path(incomplete_root) if incomplete_root else None
    if root is None or not root.is_dir():
        return []

    now = time.time() if now is None else now
    ages: dict[str, float] = {}
    for current, dirs, _files in os.walk(root, followlinks=False):
        for name in dirs:
            path = os.path.join(current, name)
            try:
                if not os.path.islink(path):
                    ages[path] = os.stat(path).st_mtime
            except OSError:
                continue

    removed: list[str] = []
    #? deepest first, so a parent is only looked at once its children have had their turn
    for path in sorted(ages, key=lambda p: p.count(os.sep), reverse=True):
        if now - ages[path] < min_age:
            continue
        try:
            os.rmdir(path)
            removed.append(path)
        except OSError:
            continue  # not empty, or not ours to remove - either way, left exactly as it was

    return removed


def remove_incomplete_downloads(
    incomplete_root: str,
    files: list[dict],
    remote_directory: str = "",
) -> dict:
    """
    Delete the partial files a cancelled download left in slskd's incomplete folder.

    **slskd keeps these on purpose.** It stores a partial download at
    `<incomplete>/<username>/<remote path>/<file>` and, when `retry.partial` is `Resume`, starts
    the next attempt at the partial file's length instead of from zero. So a leftover is a
    feature for a download that failed, and only junk for one you deliberately cancelled - which
    is why this runs on cancel and nowhere else, and why it does nothing at all unless
    SLSKD_INCOMPLETE_PATH has been pointed at that folder.

    Matching is by basename under the root rather than by rebuilding slskd's path, for the same
    reason find_local_file() does it: slskd sanitizes the remote path into the name on disk
    (`C:` becomes `C_`) and that mapping is its business, not ours.

    But it is STRICTER than find_local_file, deliberately. That one picks a best guess because
    guessing wrong means organizing the wrong file; here guessing wrong means DELETING someone
    else's download. A basename that appears more than once, or whose parent folder isn't the
    one this job was downloading from, is left alone - `01 - Intro.flac` is not a rare name.

    Every guard mirrors delete_album(), which is the other place in deadwax that removes data
    the user did not just ask for.
    """
    results: dict = {"removed": [], "skipped": [], "problem": None}

    if not incomplete_root:
        results["problem"] = "SLSKD_INCOMPLETE_PATH is not set"
        return results

    root = Path(incomplete_root)

    if not root.is_dir():
        results["problem"] = f"the incomplete folder isn't there: {incomplete_root}"
        return results

    for entry in files:
        remote_filename = entry.get("filename", "")
        own_directory, basename = split_remote_path(remote_filename)

        if not basename:
            continue

        #? the last component of the FILE's own remote folder, which is the directory name slskd
        #? nests the partial under - its disc folder, for a set shared one folder per disc (see
        #? find_local_file). The job's directory is only the fallback for a bare filename.
        folder = own_directory or remote_directory.replace("\\", "/")
        wanted_dir = folder.rstrip("/").rpartition("/")[2]

        matches = [p for p in root.rglob(basename) if p.is_file()]

        #? the strictness described above: only a file sitting in the folder this job was
        #? downloading from is unambiguously ours to remove
        if wanted_dir:
            matches = [p for p in matches if p.parent.name == wanted_dir]

        if not matches:
            continue

        if len(matches) > 1:
            results["skipped"].append(f"{basename} (several partial files share that name)")
            continue

        partial = matches[0]

        #? resolves both sides, so neither a symlink nor a ".." in the configured path can walk
        #? the delete out of the incomplete folder
        if not is_within(partial, root) or partial.resolve() == root.resolve():
            logger.warning(f"refused to remove {partial}, it is not inside {incomplete_root}")
            results["skipped"].append(f"{basename} (outside the incomplete folder)")
            continue

        try:
            partial.unlink()
            results["removed"].append(str(partial))
        except OSError as e:
            logger.warning(f"could not remove the partial file {partial}: {e}")
            results["skipped"].append(f"{basename} ({e})")

    #? Tidy the folders the partials sat in, innermost first. rmdir refuses a non-empty
    #? directory by construction, so anything still holding a file is left exactly as it was -
    #? the same reasoning as cleanup_source_dirs.
    for directory in sorted({Path(p).parent for p in results["removed"]},
                            key=lambda d: len(d.parts), reverse=True):
        while directory != root and is_within(directory, root):
            try:
                directory.rmdir()
            except OSError:
                break
            directory = directory.parent

    return results


async def organize_job(job: dict, download_root: str, library_root: str, mode: str) -> dict:
    """Plan then execute, with the logging the UI's event log surfaces."""
    label = f"{job.get('artist')} - {job.get('album')}"
    plan = await asyncio.to_thread(plan_organization, job, download_root, library_root)

    for problem in plan["problems"]:
        logger.warning(f"{label}: {problem}", extra={"frontend": True, "src": "slskd"})

    if not plan["operations"]:
        logger.error(f"nothing to organize for {label}", extra={"frontend": True, "src": "slskd"})
        return {"organized": 0, "skipped": 0, "failed": 0,
                "dry_run": mode == "dry_run", "mode": mode, "plan": plan}

    results = await asyncio.to_thread(execute_plan, plan, job.get("release") or {}, mode)

    if mode == "move":
        results["removed_dirs"] = await asyncio.to_thread(
            cleanup_source_dirs, plan, download_root, results
        )

    verb = "would organize" if results.get("dry_run") else "organized"
    companions = plan.get("companion_count") or 0
    extra = f" (+{companions} cover/sidecar file(s))" if companions else ""
    logger.info(
        f"{verb} {results['organized']} file(s){extra} for {label} into {plan['album_dir']}",
        extra={"frontend": True, "src": "slskd"},
    )

    results["plan"] = plan
    return results
